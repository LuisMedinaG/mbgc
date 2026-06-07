# Monitoring & Alerting — Progress Tracker

This doc is the **single source of truth** for resuming the monitoring work
between sessions. Each new session should:

1. `git checkout feature/monitoring` (verify clean tree)
2. Read this file top-to-bottom
3. Pick up the **Next batch** at the bottom
4. Update this file at the end of the session

If context is lost mid-batch, this file plus the spec ACIDs are enough to
re-derive the design — no prior session memory required.

---

## Branch & base

- **Branch:** `feature/monitoring` (HEAD: `58da69e`)
- **Branched from:** `dev` @ `e1df162`
- **Spec:** [`features/monitoring.feature.yaml`](../features/monitoring.feature.yaml) — pushed to acai server
- **Acai impl:** `mbgc/feature/monitoring` (8 ACIDs registered, all `pending`)
- **Design rationale:** see chat thread (ask user to paste the design summary
  if needed — it's not in the repo).
- **Stash state — read this before resuming:**
  - `stash@{0}` — `wip: pre-monitoring unrelated local changes` on `dev`
    (the original WIP from before this branch was created). Likely redundant
    with commit `4655688`; safe to drop with `git stash drop stash@{0}` if
    `git stash show -p stash@{0}` shows only files already in `4655688`.

---

## Decisions (locked in this session)

| # | Decision | Choice | Rationale |
|---|---|---|---|
| D1 | Monitoring backend | Cloud Logging + Cloud Monitoring | Free tier 50GB/mo; Cloud Run ships stdout natively; no new SDK |
| D2 | Event scope | 5xx + panics + rate-limit hits + 401 on `/auth/*` | Matches the handoff's "server-side failure + abuse signals" framing |
| D3 | Allow-list fields | `request_id`, `method`, `path`, `status`, `latency_ms`, `event` (+ `error_code`, `stack` for panic; `sync_kind`, `game_count` for BGG) | Strict GDPR posture |
| D4 | Failure mode | Drop on backpressure, emit `event=meta_warning` | Fail-open per handoff |
| D5 | Alert config | As code (`infra/monitoring.tf`) | PR review on alert changes |
| D6 | Notifications | Email (start here) | Cheapest; revisit if alerts become noisy |
| D7 | Cost ceiling | 50GB Cloud Logging free tier + budget alert at 40GB | Headroom before throttling |
| D8 | Test bar | Unit tests for redaction + `Record` helper only | Matches existing pkg/shared/httpx test style |
| D9 | Compliance | GDPR-strict — strip IP, email, username, headers, cookies, body | D3 is a direct consequence |
| D10 | Scope | HTTP layer + BGG importer sync observability | Explicitly requested |
| D11 | Auth-probe alert signal | Aggregate `event=auth_failure` at route level (no per-IP) | Resolves IP-vs-GDPR conflict |
| D12 | `WriteError` refactor | Wrapper middleware observes 5xx, leaves signature alone | Avoids touching every handler |
| D13 | `user_id` in events | **Disabled by default** (Supabase UUID is non-PII but stays out until asked) | Strict-default |
| D14 | Pacing | Easiest → hardest, in batches, with this doc as handoff | User request |

---

## ACID map (from spec)

| ACID | Summary | Batch |
|---|---|---|
| `monitoring.SINK.1` | 5xx emits `event=server_error` | 3 | **done** |
| `monitoring.SINK.2` | Recovered panic emits `event=panic` w/ stack | 3 | **done** |
| `monitoring.SINK.3` | Rate-limit emits `event=rate_limit` | 3 | **done** |
| `monitoring.SINK.4` | 401 on `/auth/*` emits `event=auth_failure` | 3 | **done** |
| `monitoring.SINK.5` | BGG sync start/ok/error events | 5 |
| `monitoring.SINK.6` | Every event carries allow-list fields | 2, 3 | **done** |
| `monitoring.SINK.7` | No field outside allow-list is ever serialized | 2, 3 | **done** |
| `monitoring.REDACTION.1` | Auth/Cookie/XFF/Set-Cookie never read or logged | 2 |
| `monitoring.REDACTION.2` | user_id, username, client IP never included | 2 |
| `monitoring.REDACTION.3` | BGG_TOKEN, BGG_COOKIE, SERVICE_ROLE_KEY never included | 2 |
| `monitoring.REDACTION.4` | Query strings dropped; path is logged as-is | 2 |
| `monitoring.REDACTION.5` | Allow-list is the single source of truth, enforced at `Record` | 2 |
| `monitoring.ALERTS.1` | Panic spike > 3 in 5 min → email | 6 |
| `monitoring.ALERTS.2` | 5xx ratio > 1% over 5 min → email | 6 |
| `monitoring.ALERTS.3` | Auth probe `event=auth_failure` on `/auth/*` > 5× baseline / 1 min → email | 6 |
| `monitoring.ALERTS.4` | Rate-limit global rate > 100/min sustained 5 min → email | 6 |
| `monitoring.ALERTS.5` | Budget alert: ingestion > 40GB/mo → email | 6 |
| `monitoring.OBSERVABILITY.1` | Meta-warning on event emission failure | 4 | **done** |
| `monitoring.OBSERVABILITY.2` | Heartbeat every 5 min | 4 | **done** |
| `monitoring.FAIL_OPEN.1` | Blocked stdout/buffer does not propagate to request | 4 | **done** |
| `monitoring.FAIL_OPEN.2` | Handler slog error does not affect request | 4 | **done** |
| `monitoring.COST.1` | Non-401 4xx at info, not error | 3 | **done** |
| `monitoring.COST.2` | Sampling deferred to P2 | (out of P0) |

---

## Batches (easiest → hardest)

| # | Batch | Files touched | ACIDs | Status |
|---|---|---|---|---|
| 1 | Spec only | `features/monitoring.feature.yaml` | — | **done (58da69e)** |
| 2 | Redaction core | `pkg/shared/httpx/observe.go`, `observe_test.go` (NEW) | SINK.6, SINK.7, REDACTION.1-5 | **done (549781c)** ⚠ status blocked |
| 3 | Wire into middleware | `pkg/shared/httpx/middleware.go`, `rate_limiter.go` (PATCH) | SINK.1-4, SINK.6-7, COST.1 | **done (670fbd0)** |
| 4 | Slog JSON handler + heartbeat | `services/api/internal/observe/` (NEW), `services/api/cmd/server/main.go` (PATCH) | OBSERVABILITY.1-2, FAIL_OPEN.1-2 | **done (7e734a5)** |
| 5 | BGG sync observability | `services/api/internal/importer/service.go` (PATCH) | SINK.5 | pending |
| 6 | Infra as code | `infra/monitoring.tf` (NEW) | ALERTS.1-5 | pending |
| 7 | Runbook | `docs/runbook/monitoring.md` (NEW) | — | pending |

Each batch ends with: code + tests + commit + `acai set-status` for the ACIDs
the batch touched + `acai push --all` + this doc updated.

---

## Resume from here — current batch

### Batch 1 — Spec (DONE)
- [x] Write `features/monitoring.feature.yaml` mirroring `auth.feature.yaml` style
- [x] `npx @acai.sh/cli push --all` (registers feature + ACIDs on the server)
- [x] `git commit -m "feat(monitoring): add spec and progress tracker"`
- [x] No `acai set-status` — no ACIDs completed, only registered
- [x] Update this doc: Batch 1 done, Batch 2 next

### Batch 2 — Redaction core (DONE — `549781c`)
- [x] `pkg/shared/httpx/observe.go` — `Record(r, event, level, attrs...)` with allow-list
- [x] `pkg/shared/httpx/observe_test.go` — 11 tests, all passing
- [x] `make test-v` in services/api and `go test -race` in pkg/shared both green
- [x] `make tidy` clean
- [x] `acai push --all` — refs registered (33 total on monitoring feature, up from 23)
- [ ] **⚠ `acai set-status` BLOCKED** by a CLI bug (see Known issues below). All 7
      ACIDs in this batch are `status: null` on the server even though code+tests
      are done. They are correctly registered with code refs.
- [x] Update this doc: Batch 2 done; advance to Batch 3.

### Batch 3 — Wire into middleware (DONE — `670fbd0`)
- [x] Patch `pkg/shared/httpx/middleware.go`:
  - `Recover` — replace `slog.Error("panic recovered", ...)` with
    `Record(r, "panic", slog.LevelError, "value", v, "stack", string(debug.Stack()))`
    — ref `monitoring.SINK.2`.
  - `Logger` — replace `slog.Info("request", ...)` with conditional `Record`:
    - status >= 500 → `Record(r, "server_error", slog.LevelError, ...)` — ref `monitoring.SINK.1`.
    - status == 401 && path starts with `/auth/` → `Record(r, "auth_failure", slog.LevelWarn, ...)` — ref `monitoring.SINK.4`.
    - other 4xx → `Record(r, "request", slog.LevelInfo, ...)` — ref `monitoring.COST.1`.
    - 2xx/3xx → `Record(r, "request", slog.LevelInfo, ...)`.
  - Decision: skip the new `ObserveStatus` middleware; `Logger` naturally sees 5xx via `statusWriter`. D12 satisfied.
- [x] Patch `pkg/shared/httpx/rate_limiter.go`:
  - Inside the limiter-rejection branch, before `WriteError`, call
    `Record(r, "rate_limit", slog.LevelWarn)` — ref `monitoring.SINK.3`.
- [x] Update existing tests in `middleware_test.go`:
  - `TestRecover_WithPanic` — assert the captured slog has `event=panic`.
  - `TestLogger` — 2xx/3xx keeps `event=request` at `INFO` level.
  - Added `TestLogger_5xxEmitsServerError`, `TestLogger_Auth401EmitsAuthFailure`, `TestLogger_4xxNonAuthIsInfo`.
  - Added `TestRateLimiter_EmitsRateLimitEvent` (burst=0 to force 429).
- [x] All 46 tests passing (`go test -v -race ./httpx/...` in pkg/shared).
- [x] `make tidy` clean; `make test-v` green in services/api.
- [x] `git commit -m "feat(monitoring): wire panic, request, rate_limit, auth_failure through Record"` (`670fbd0`).
- [x] `git push` succeeded.
- [ ] `acai push --all` — skipped (needs auth token; same issue as Batch 2).
- [x] Update this doc: Batch 3 done; advance to Batch 4.

### Batch 4 — Slog JSON handler + heartbeat (DONE — `7e734a5`)
- [x] New package `services/api/internal/observe/` with:
  - `NewHandler()` — returns a fail-open JSON slog handler. Primary writes to stdout; on error, emits `event=meta_warning` to stderr and returns nil. — ref `monitoring.OBSERVABILITY.1`, `monitoring.FAIL_OPEN.1`, `monitoring.FAIL_OPEN.2`.
  - `Heartbeat(ctx, interval)` — goroutine that emits `event=heartbeat` immediately and every `interval` until ctx is cancelled. — ref `monitoring.OBSERVABILITY.2`.
  - 5 tests, all passing:
    - `TestFailOpenHandler_PrimaryFailureReturnsNil`
    - `TestFailOpenHandler_EmitsMetaWarningOnPrimaryFailure`
    - `TestFailOpenHandler_NoMetaOnPrimarySuccess`
    - `TestFailOpenHandler_MetaFailureAlsoReturnsNil` (meta sink also failing)
    - `TestHeartbeat_EmitsOnTick` (initial + ticks + ctx-cancel stop)
- [x] Patch `services/api/cmd/server/main.go`:
  - First line of `main()`: `slog.SetDefault(slog.New(observe.NewHandler()))` — so even config-load failures are captured.
  - Heartbeat goroutine started right after, with 5-min interval, cancelled on shutdown.
- [x] `make tidy` clean; `make test-v` green in services/api.
- [x] `git commit -m "feat(monitoring): add fail-open JSON handler and 5-min heartbeat"` (`7e734a5`).
- [x] Update this doc: Batch 4 done; advance to Batch 5.

### Batch 5 — BGG sync observability (NEXT)
Scope: emit `sync_start`, `sync_ok`, `sync_error` events from `services/api/internal/importer/service.go` at the right points so the importer sync path is observable. One ACID — `monitoring.SINK.5`.

The importer.Service.Sync method (the real entry point the handler calls) is
the place. It currently has a `// TODO: fetch BGG collection, create games via
gameSvc` placeholder. When that's implemented, the wire points are:

- Beginning of `Sync` (after BGG.Available + rate-limit pass):
  `Record(r, "sync_start", slog.LevelInfo, "sync_kind", kind)` where
  `kind = "incremental"` for normal syncs and `kind = "full_refresh"` when
  the caller passed `fullRefresh=true`. — ref `monitoring.SINK.5`.
- After successful return: `Record(r, "sync_ok", slog.LevelInfo, "sync_kind", kind, "game_count", result.Imported)`.
- On any error path (rate-limit, BGG unconfigured, fetch failure, store error):
  `Record(r, "sync_error", slog.LevelWarn|Error, "sync_kind", kind, ...)` where
  the level matches the severity of the error (rate-limit = warn, fetch/store
  failure = error).

Note: the `Service.Sync` method does not currently have a `*http.Request`
parameter — it has a `context.Context` and a `userID` string. To use `Record`,
we need either:
1. Pass `r *http.Request` through the handler call (small refactor — handler
   already has it).
2. Use a `Record` variant that takes just a context + attrs. Out of scope
   for this batch; the existing `Record(r, event, level, attrs...)` signature
   should be used with `r` plumbed in.

Decision: go with option 1 — plumb the request through. The handler call
already has `r` and the service is small. This keeps the single Record
signature and preserves the "no helper-managed field" guarantee.

CSV paths (`ParseCSVPreview`, `ImportBGGIDs`) are explicitly out of scope
per D10 (HTTP-layer + BGG importer sync observability — the CSV paths are
not "sync" semantics; they're import. If we want them later, add a
separate ACID in P2).

- [ ] Patch `services/api/internal/importer/service.go`:
  - `Sync(ctx, userID, bggUsername, isAdmin, fullRefresh, ...)` → add `r *http.Request` param
  - Wire `Record(r, "sync_start", ...)` after rate-limit passes.
  - Wire `Record(r, "sync_ok", ...)` on success.
  - Wire `Record(r, "sync_error", ...)` on each error return path.
- [ ] Patch `services/api/internal/importer/handler.go` to pass `r` to `Sync`.
- [ ] Update tests in `handler_test.go` to mock/capture the Record call.
- [ ] `make test-v` and `make tidy`.
- [ ] Git commit, push.
- [ ] Update this doc: Batch 5 done; advance to Batch 6.

---

## Known issues

### `acai set-status` CLI bug with slash in branch name
The acai CLI's `--impl` parser treats `<x>/<y>` as a `<product>/<implementation>`
namespace selector. Since the branch name is `feature/monitoring` (with a slash),
the CLI parses it as `product=feature, impl=monitoring`, which does not match
the actual server-side implementation_name. As a result, all `acai set-status`
calls from this branch fail with either:
- "Conflicting product selectors" (when `--product mbgc --impl feature/monitoring` is used)
- "Resource not found" (when `--impl mbgc/feature/monitoring` is used)
- "Missing product selector" (when no product is specified and `--impl` is treated as a name)

**Impact:** ACID status updates (pending → completed) are blocked. The ACIDs
themselves, the spec, and the code refs are correctly registered via
`acai push --all`. The code, tests, and commits are the source of truth.

**Workarounds:**
1. Set status manually on the dashboard at https://app.acai.sh once all batches
   are complete.
2. Rename the branch from `feature/monitoring` to `feature-monitoring` (dash) and
   re-push. This requires updating this doc and re-running the worktree.
3. Use the acai HTTP API directly (the public path is not currently documented;
   direct curl to `https://app.acai.sh/api/*` returns 404).

**Status (Batch 2):** 7 ACIDs pending on the server, code+tests complete locally.
This will accumulate across all batches; a single dashboard sweep at the end is
the cleanest fix.

---

## Conventions reminder (from AGENTS.md / CLAUDE.md)

- `// ref: <ACID>` comments in code, immediately above the implementing block
- Test names reference the ACID(s) they cover, e.g. `TestRecord_DropsDisallowedKeys`
- `slog` only — never `log.Printf` / `fmt.Println`
- `fmt.Errorf("%w", err)` + `errors.Is` for wrapping
- `pkg/shared/apierr` for error sentinels; `httpx.WriteError` for HTTP errors
- Run `make test-v` in `services/api` after touching `pkg/shared` (go.work replace
  directive means services/api sees the local pkg/shared immediately, but
  `go.sum` still needs a sync via `make tidy`)
- All commits: imperative, ≤50 chars, prefix `feat:` / `fix:` / `chore:` / `refactor:`
- Branch off `dev`; PR target `dev`; never push to `main`

## Test / lint commands

```sh
# from services/api/
make test-v          # go test -v -race ./...
make lint            # golangci-lint run (if configured)
make tidy            # go mod tidy (after touching pkg/shared)

# from repo root
make test            # go tests for pkg/shared + services/api
make lint            # top-level lint
```

## Open thread (do not block on this)

The handoff doc items #2 (dep scanning) and #3 (Content-Type enforcement)
remain unstarted. **Do not work on them in this branch** — different feature,
different branch. Track them in `pending-security-design.md` as before.
