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
| `monitoring.SINK.1` | 5xx emits `event=server_error` | 3 |
| `monitoring.SINK.2` | Recovered panic emits `event=panic` w/ stack | 3 |
| `monitoring.SINK.3` | Rate-limit emits `event=rate_limit` | 3 |
| `monitoring.SINK.4` | 401 on `/auth/*` emits `event=auth_failure` | 3 |
| `monitoring.SINK.5` | BGG sync start/ok/error events | 5 |
| `monitoring.SINK.6` | Every event carries allow-list fields | 2, 3 |
| `monitoring.SINK.7` | No field outside allow-list is ever serialized | 2, 3 |
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
| `monitoring.OBSERVABILITY.1` | Meta-warning on event emission failure | 4 |
| `monitoring.OBSERVABILITY.2` | Heartbeat every 5 min | 4 |
| `monitoring.FAIL_OPEN.1` | Blocked stdout/buffer does not propagate to request | 4 |
| `monitoring.FAIL_OPEN.2` | Handler slog error does not affect request | 4 |
| `monitoring.COST.1` | Non-401 4xx at info, not error | 3 |
| `monitoring.COST.2` | Sampling deferred to P2 | (out of P0) |

---

## Batches (easiest → hardest)

| # | Batch | Files touched | ACIDs | Status |
|---|---|---|---|---|
| 1 | Spec only | `features/monitoring.feature.yaml` | — | **done (58da69e)** |
| 2 | Redaction core | `pkg/shared/httpx/observe.go`, `observe_test.go` (NEW) | SINK.6, SINK.7, REDACTION.1-5 | **next** |
| 3 | Wire into middleware | `pkg/shared/httpx/middleware.go`, `rate_limiter.go` (PATCH) | SINK.1-4, SINK.6-7, COST.1 | pending |
| 4 | Slog JSON handler + heartbeat | `services/api/cmd/server/main.go` (PATCH) | OBSERVABILITY.1-2, FAIL_OPEN.1-2 | pending |
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

### Batch 2 — Redaction core (NEXT)
Scope: pure helper + tests. No wiring into middleware yet. The helper is the
contract the rest of the design depends on, so this is the most important batch
to get right.

- [ ] Create `pkg/shared/httpx/observe.go` with:
  - `Record(r *http.Request, event string, level slog.Level, attrs ...any)` —
    emits via `slog.Log(ctx, level, event, ...)` after filtering attrs through
    the allow-list. Always includes `request_id`, `method`, `path` from the
    request. Never reads `Authorization`, `Cookie`, `X-Forwarded-For`,
    `Set-Cookie`, query string, or body. The function signature does not
    accept a header map or body, so redaction is enforced by API shape.
  - `allowedAttrs` package-level map (D11/D13 defaults: no `user_id`, no IP).
  - `// ref: monitoring.REDACTION.5` on the allow-list declaration.
  - `// ref: monitoring.SINK.6` on the helper signature.
- [ ] Create `pkg/shared/httpx/observe_test.go` with tests (D8 — unit only):
  - `TestRecord_DropsDisallowedKeys` — pass `api_key=…`, `cookie=…`; assert
    they do not appear in the captured slog output.
  - `TestRecord_IncludesRequestIDMethodPath` — assert required fields are
    always present.
  - `TestRecord_AllowsKnownOptionalKeys` — `error_code`, `stack`, `sync_kind`,
    `game_count`, `latency_ms`, `status` pass through.
  - `TestRecord_NilRequestSafe` — guard against nil r (defensive; panic site
    tests will exercise this).
  - `TestRecord_RespectsSlogLevel` — `error` vs `warn` vs `info` levels flow
    to the handler's `Enabled` check.
- [ ] Run `make test-v` from `services/api/` to verify (the test file is in
  pkg/shared, but `go.work` lets services/api see it; the existing test target
  picks it up).
- [ ] `make tidy` in `services/api/`.
- [ ] `git commit -m "feat(monitoring): add Record helper with allow-list"`
- [ ] `acai set-status` for the 7 ACIDs Batch 2 completes:
  `monitoring.SINK.6, SINK.7, REDACTION.1, REDACTION.2, REDACTION.3,
  REDACTION.4, REDACTION.5`
- [ ] `acai push --all`
- [ ] Update this doc: Batch 2 done; advance to Batch 3.

### Verify before next session
```sh
git status                        # working tree: only WIP from prior session, no new changes
git log --oneline -3              # helper commit should be HEAD
npx @acai.sh/cli feature monitoring --json --include-refs   # ACIDs visible, some marked done
cd pkg/shared && go test -v -race ./httpx/...               # tests pass
```

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
