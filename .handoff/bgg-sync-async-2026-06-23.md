# Async BGG Sync — Implementation Handoff

Issue: [#51](https://github.com/LuisMedinaG/mbgc/issues/51). Full context below so this can
be picked up in a fresh session without re-deriving the codebase analysis.

## Problem

`services/api/internal/importer/service.go` — `Sync` blocks the request for the full
duration of fetching + parsing + upserting.

**Correction to original issue estimate:** `bgg.go` `FetchGames` already batches 20 BGG IDs
per XML API request, not 1-per-request. At the global 2 req/s BGG limit (`bggRPS` in
`bgg.go`), 500 games ≈ 25 requests ≈ ~13s, not ~250s. Cloud Run's default request timeout
(300s) is not in imminent danger today. This is a **foundation-for-scale issue**, not an
active outage — worth doing right, not fast. Full refreshes (which skip the dedup check and
re-fetch everyone) and BGG slow responses/429 retries are the realistic paths to a
long-running sync.

## Decisions made (do not re-litigate without new info)

- **No Redis.** Postgres (Supabase) is already in use and the importer owns its own schema
  (`importer.*`). A job table satisfies "survives Cloud Run restart" with zero new infra
  dependencies. Adding Redis would be a new external service for no gain at this scale —
  ask-first territory per AGENTS.md, and not worth asking.
- **No worker pool.** BGG's rate limit is **global, not per-connection** (`bggRPS = 2` in
  `bgg.go`, shared `throttledTransport`). Concurrent workers all hitting BGG just contend
  for the same budget — net throughput doesn't improve, risk of 429/ban does. One job
  processed at a time, FIFO via `FOR UPDATE SKIP LOCKED`.
- **Trigger mechanism: Cloud Tasks**, not an always-on in-process worker. Cloud Run scales
  `min_instance_count = 0` today (see `infra/modules/cloud-run/main.tf`) — CPU is throttled
  to ~0 outside request handling, so a detached goroutine can't reliably finish background
  work, and keeping an instance always-on (`min_instances=1` + `--no-cpu-throttling`) means
  paying 24/7 for a service one person uses. Cloud Tasks keeps `$0` idle cost (1M ops/mo free
  tier), gives durable retries, and scales cleanly if this ever needs more throughput (e.g.
  App Store launch) — dial queue concurrency, no code rewrite.
  - **Interim/lazier option, compatible but not chosen:** Cloud Scheduler cron hitting the
    same internal worker endpoint every ~1 min instead of Cloud Tasks. Same job table, same
    processor code, $0 idle, costs only added latency + throughput ceiling. Swapping
    cron → Cloud Tasks later only touches the trigger, not the processing code. Use this if
    the goal is shipping the durable core before doing the Terraform/Cloud Tasks work.
- Processing logic does not change shape — it's today's `Sync` body in `service.go`,
  refactored to read/write a job row instead of returning directly.

## Implementation plan

### Phase 1 — Durable job core (pure Go + migration, no infra changes)

1. New migration `services/api/migrations/008_import_jobs.{up,down}.sql`:
   ```sql
   CREATE TABLE importer.import_jobs (
     id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
     user_id text NOT NULL,
     status text NOT NULL DEFAULT 'pending',  -- pending|running|completed|failed
     full_refresh boolean NOT NULL DEFAULT false,
     imported int NOT NULL DEFAULT 0,
     skipped int NOT NULL DEFAULT 0,
     failed int NOT NULL DEFAULT 0,
     total int NOT NULL DEFAULT 0,
     processed int NOT NULL DEFAULT 0,
     error text,
     created_at timestamptz NOT NULL DEFAULT now(),
     updated_at timestamptz NOT NULL DEFAULT now()
   );
   CREATE INDEX idx_import_jobs_user_created ON importer.import_jobs (user_id, created_at DESC);
   CREATE INDEX idx_import_jobs_pending ON importer.import_jobs (status, created_at) WHERE status = 'pending';
   ```
   Down migration drops the table.

2. `services/api/internal/importer/store.go` — add:
   - `CreateJob(ctx, userID string, fullRefresh bool) (jobID string, err error)`
   - `GetJob(ctx, userID, jobID string) (*ImportJob, error)` — must filter by `user_id`
     (AGENTS.md: "Include `user_id` in every query on user-owned data").
   - `ClaimNextJob(ctx) (*ImportJob, error)` — atomic claim:
     ```sql
     UPDATE importer.import_jobs SET status = 'running', updated_at = now()
     WHERE id = (
       SELECT id FROM importer.import_jobs
       WHERE status = 'pending' ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1
     )
     RETURNING id, user_id, full_refresh, ...
     ```
     Returns `nil, nil` (no error) when no pending job — caller treats as "nothing to do."
   - `UpdateJobProgress(ctx, jobID string, processed, total int) error`
   - `FinishJob(ctx, jobID string, imported, skipped, failed int, jobErr error) error` —
     sets `status = completed` or `failed`, sanitized `error` string (never raw
     `err.Error()` from internals — `apierr` convention applies here too; write a short
     stable message).

3. `services/api/internal/importer/model.go` — add `ImportJob` struct mirroring the table;
   reuse existing `SyncResult` shape for the terminal counts so the API response stays
   consistent.

4. `services/api/internal/importer/service.go` — split `Sync`:
   - `Enqueue(r *http.Request, userID string, isAdmin, fullRefresh bool, limitUser,
     limitAdmin int) (jobID string, err error)`: keeps the existing `Available()` check,
     `CheckRateLimit`, the `sync_start` monitoring event, then `store.CreateJob` and returns
     the job ID immediately. Do **not** call `RecordSync`/`LogSync` here — move those to job
     completion so a job that never runs doesn't consume the daily quota.
   - `ProcessJob(ctx context.Context, job *ImportJob) error`: the current body of `Sync`
     from "Fetch the user's BGG username" onward, unchanged fetch/upsert logic, but writes
     `UpdateJobProgress` after each batch and calls `FinishJob` at the end instead of
     returning `*SyncResult` directly. Keep the same `sync_ok`/`sync_error` monitoring events
     (`httpx.Record`) — independent of the job table, still useful for ops visibility.
     `RecordSync`/`LogSync` move here, called once on terminal success.
   - Keep `ImportBGGIDs` and `ParseCSVPreview` untouched — CSV import path is small/bounded
     (`maxImportBatch = 100` in `handler.go`) and out of scope for this issue.

### Phase 2 — Endpoints + backward compat

5. `services/api/internal/importer/handler.go`:
   - `POST /api/v1/import/sync`:
     - `?sync=sync` query param → preserve exact current synchronous behavior (old code
       path, 200 + `SyncResult` body) for the deprecation window the issue calls for.
     - default (no param, or anything else) → call `Enqueue`, return **202** with
       `httpx.New(struct{ JobID string; Status string }{...})`.
   - New `GET /api/v1/import/sync/{job_id}`: `httpx.RequireUserID`,
     `store.GetJob(ctx, userID, jobID)`, 404 (via `apierr` sentinel, not raw error) if not
     found or not owned by caller, else 200 with job status + counts +
     `processed`/`total`.
   - New internal endpoint `POST /internal/import/work` — Cloud Tasks invocation target.
     Calls `store.ClaimNextJob`, if nil job returns 204 (nothing pending), else `ProcessJob`
     then returns 200. **Auth: must verify the request comes from Cloud Tasks (OIDC token
     from the runtime SA), not a user JWT** — this touches `services/api/internal/jwt/`
     middleware, which AGENTS.md flags as "ask first: auth flow modifications." Surface this
     explicitly to the user before implementing — needs a new verification branch (e.g.
     check `Authorization: Bearer <OIDC token>` against the Cloud Tasks invoker SA email)
     distinct from the Supabase JWKS path used everywhere else.

### Phase 3 — Infra (separate PR, per `infra/AGENTS.md`: one change = one PR)

6. `infra/modules/cloud-tasks/` (new module) or inline in `environments/prod/main.tf`:
   - `google_cloud_tasks_queue` with `rate_limits.max_concurrent_dispatches = 1` (matches
     BGG's global 2 req/s ceiling — no benefit to running jobs concurrently, see "Decisions
     made" above).
   - Retry config with backoff for transient BGG failures.
   - Runtime SA (`GCP_RUNTIME_SA_API`, already exists per `infra/AGENTS.md` secrets list)
     needs `roles/cloudtasks.enqueuer` to create tasks, and the queue's task target needs
     OIDC token config pointing at `/internal/import/work` authenticated as that same SA
     (self-invocation pattern — Cloud Run service calling itself via Cloud Tasks).
   - `min_instance_count` stays `0` — do not touch `infra/modules/cloud-run/main.tf` scaling
     block (ignored by lifecycle anyway, owned by service CI/CD).
   - Run `terraform plan` and show output before `apply`, per infra rules. New resource, not
     a destroy/recreate, so lower risk — still review.

### Phase 4 — Web client

7. `web/src/lib/api.ts` — `syncBGG` return shape changes to `{job_id, status}` instead of
   `SyncResult` directly (unless `sync=sync` fallback is used). Add
   `getSyncJob(jobId): Promise<ImportJob>` hitting the new GET endpoint.
8. `web/src/hooks/` — new hook (or extend wherever `syncBGG` is currently called — check for
   an `useImport`-style hook, else add alongside `useProfile`/`useCollections` pattern) using
   TanStack Query: mutation to enqueue, then `useQuery` with `refetchInterval` polling the
   job while `status` is `pending`/`running`, stopping on `completed`/`failed`. Replace
   current spinner-until-resolve UX with progress display (`processed`/`total`) where the
   sync button lives (`ProfilePage.tsx` per current grep — BGG username/sync UI is there).

## Constraints to respect throughout (from AGENTS.md / CLAUDE.md)

- Every query on `import_jobs` filters by `user_id` — no exceptions.
- Use `apierr` sentinels for all new error paths; never expose raw `err.Error()` in
  `FinishJob`'s stored error or in HTTP responses.
- Use `httpx.WriteJSON`/`WriteError`, never raw `json.NewEncoder`.
- `make tidy && make test-v` in `services/api` before PR (no `pkg/shared` touched here, so
  no cross-module concern).
- New handler needs tests mocking the store interface (no DB), per existing pattern
  (`handler_test.go`).
- Coverage threshold 50% — this is a sizeable new surface, write tests alongside, not after.
- Branch from `dev`, prefix `feature/*`, PR targets `dev`. Infra change (Phase 3) is a
  **separate PR**.
- The internal-endpoint auth change (step 5, Cloud Tasks OIDC verification) should be
  confirmed with the user before implementation — it's an auth-flow change per the
  "ask first" list.

## Open question for implementer

Phase 3 can be deferred — ship Phases 1+2 with the Cloud Scheduler cron interim trigger if
the goal is getting the durable core live without touching Terraform yet. Endpoint code is
identical either way; only the Terraform resource differs. Confirm with user which trigger
to build before starting Phase 2's internal endpoint.

## Backward compat

Keep `?sync=sync` synchronous path through the deprecation period. Remove in a follow-up
issue once web client fully migrates to polling.
