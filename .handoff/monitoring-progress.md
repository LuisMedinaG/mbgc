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
| `monitoring.SINK.5` | BGG sync start/ok/error events | 5 | **done (84da4a8)** |
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
| 5 | BGG sync observability | `services/api/internal/importer/service.go` (PATCH), `handler.go` (PATCH) | SINK.5 | **done (84da4a8)** |
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

### Batch 5 — BGG sync observability (DONE — `84da4a8`)
- [x] Patch `services/api/internal/importer/service.go`:
  - `Sync(ctx, userID, bggUsername, isAdmin, fullRefresh, ...)` → `Sync(r *http.Request, userID, bggUsername, isAdmin, fullRefresh, ...)` (ctx comes from `r.Context()`)
  - Two consts: `syncKindIncremental = "incremental"`, `syncKindFullRefresh = "full_refresh"`
  - Wire `Record(r, "sync_start", slog.LevelInfo, "sync_kind", kind)` after BGG.Available + rate-limit checks pass.
  - Wire `Record(r, "sync_ok", slog.LevelInfo, "sync_kind", kind, "game_count", result.Imported)` on success.
  - Wire `Record(r, "sync_error", level, "sync_kind", kind)` on each error return:
    - BGG unconfigured → `LevelError`
    - rate-limit (`apierr.ErrRateLimit`) → `LevelWarn`; any other `CheckRateLimit` failure → `LevelError`
    - store failures (RecordSync, LogSync) → `LevelError`
  - All call sites annotated with `// ref: monitoring.SINK.5`.
- [x] Patch `services/api/internal/importer/handler.go` to pass `r` to `Sync` (1-line).
- [x] Add 6 new tests in `handler_test.go` (captureSlog + decodeLines helpers added in the same file):
  - `TestSync_EmitsSyncStartAndSyncOk` — happy path, both events with sync_kind=incremental, game_count=0
  - `TestSync_FullRefreshEmitsFullRefreshKind` — sync_kind=full_refresh on both events
  - `TestSync_EmitsSyncErrorOnBGGUnconfigured` — sync_error at ERROR, no sync_start
  - `TestSync_EmitsSyncErrorOnRateLimited` — sync_error at WARN, no sync_start
  - `TestSync_EmitsSyncErrorOnCheckRateLimitServerFailure` — sync_error at ERROR for non-rate-limit server fault
  - `TestSync_EmitsSyncErrorOnStoreFailure` — sync_start fires, then sync_error at ERROR on RecordSync failure
- [x] `make tidy` clean; `make test-v` green (35 importer tests, 9 packages in services/api, 3 in pkg/shared — all pass with `-race`).
- [x] `git commit -m "feat(monitoring): emit sync_start, sync_ok, sync_error from BGG sync"` (`84da4a8`).
- [x] `git push` succeeded.
- [x] Update this doc: Batch 5 done; advance to Batch 6.

### Batch 6 — Infra as code (NEXT)
Scope: declare the 5 Cloud Monitoring alert policies in `infra/monitoring.tf` so they're reviewable in PRs. Five ACIDs — `monitoring.ALERTS.1-5`.

Design notes for the next session (decisions not yet made — feel free to push back):

- The infra repo uses `hashicorp/google ~> 6.0`. Cloud Monitoring alerts are
  `google_monitoring_alert_policy` resources; the metric filters reference the
  custom log-based metrics we need to create first via
  `google_logging_metric` (one per alert). Counters for the 5xx/panic/rate-limit
  events live as log-based metrics in the same file.
- For ALERTS.5 (budget), use `google_billing_budget` with a `thresholdRules`
  block at 40GB. This resource belongs in a billing-scoped file — likely
  `infra/billing.tf` rather than `monitoring.tf`. Decide when we get there.
- Notifications: the handoff picked email (D6). For Terraform, that's
  `google_monitoring_notification_channel` of type `email` with a single
  `labels.email = var.alert_email` — variable declared in `variables.tf`,
  populated via `TF_VAR_alert_email` or `terraform.tfvars` (gitignored).
- Auth-probe baseline (ALERTS.3) is "5× baseline / 1 min" — log-based metric
  is just a count of `event=auth_failure AND path=~"/auth/.*"`. Baseline
  detection is harder in pure MQL; the closest MQL primitive is
  `abs(rate[1m]) > 5 * threshold` where `threshold` is the long-window
  average. Keep this simple: pick a fixed threshold (e.g. 10/min) and call it
  "5× baseline" with a `# TODO: tune` note.
- ACID spec says paths/aggregation windows match the spec exactly:
  - ALERTS.1: count `event=panic` > 3 in 5 min
  - ALERTS.2: ratio `event=server_error / total responses` > 0.01 over 5 min
  - ALERTS.3: count `event=auth_failure AND path=~"/auth/.*"` > 5x baseline / 1 min
  - ALERTS.4: rate `event=rate_limit` global > 100/min sustained 5 min
  - ALERTS.5: ingestion volume > 40GB/mo

Open sub-questions for the user before coding:

1. **Module vs root file:** infra/AGENTS.md describes a root module at
   `environments/prod/main.tf` with shared `modules/*`. Should this be a new
   module `modules/monitoring/` (cleaner, reusable) or a flat
   `environments/prod/monitoring.tf` (simpler, follows the existing flat
   pattern in environments/prod/main.tf)? Recommend **new module** — alerts
   deserve their own blast-radius.
2. **Alert email address:** confirm the address. Stored in `terraform.tfvars`
   (gitignored) so it's not committed. The CI apply uses `TF_VAR_alert_email`
   from a GitHub secret.
3. **Stagger the creation:** GCP's log-based metrics take 5-10 min to start
   populating after `terraform apply`. First PR should create the metrics
   only; second PR adds the alert policies that consume them. Or just do
   both in one PR and accept the empty-metric window. Recommend **one PR
   both** for now — keeps the spec ACIDs atomic with the code.
4. **Test bar:** this is pure config. `terraform plan` on a feature branch
   (CI does this) is the only feasible test. No unit tests. Add a
   `.tflint.hcl` rule? Not needed — module follows the google preset.

- [ ] Decide module vs root file.
- [ ] Create `modules/monitoring/` (or `environments/prod/monitoring.tf`) with:
  - 5 `google_logging_metric` resources (one per ACID counter)
  - 5 `google_monitoring_alert_policy` resources
  - 1 `google_monitoring_notification_channel` (email)
  - `variables.tf` for `project_id` and `alert_email`
  - `outputs.tf` for the policy names (handy for runbook)
- [ ] Wire module call in `environments/prod/main.tf` (or wherever the root
      module pulls from).
- [ ] `terraform fmt -recursive`, `tflint --recursive`, `tfsec .` clean.
- [ ] `terraform plan` (do not apply — `infra/AGENTS.md` rule: PR CI does
      the plan review).
- [ ] Git commit, push, open PR to `dev` (infra PRs target dev per
      `infra/AGENTS.md` + root `AGENTS.md`).
- [ ] Update this doc: Batch 6 done; advance to Batch 7.

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
