# Architecture flaw assessment

Scope: senior engineering review of the current `mbgc` repo architecture.

Scale:
- Criticality: `P0` = urgent security/data-loss risk, `P1` = high product/platform risk, `P2` = medium maintainability risk, `P3` = cleanup.
- Size: `S` = hours, `M` = 1-3 days, `L` = 1-2 weeks, `XL` = larger design/migration.

## Summary

The repo has a strong macro shape: React SPA -> Go API -> Supabase Postgres.

The main backend design is intentionally simple and operationally sane.

The largest weakness is auth-token handling in the web app.

The second largest weakness is drift between documented architecture and implemented architecture.

The third largest weakness is uneven adherence to frontend state-management conventions.

## Findings

| ID | Flaw | Criticality | Size | Primary path(s) | Why it matters | Recommended fix |
|---|---|---:|---:|---|---|---|
| F-01 | Refresh token was stored in `localStorage`; first remediation is now implemented on this branch. | P0 | L | `web/src/lib/api.ts`, `web/src/contexts/AuthContext.tsx`, `services/api/internal/auth/handler.go`, `services/api/internal/httpx/middleware.go` | XSS could steal both access and refresh tokens, turning a UI bug into durable account takeover. | Keep refresh token in an `HttpOnly`, `SameSite` cookie; keep access token memory-only; continue with end-to-end auth regression tests. |
| F-02 | Auth docs contradicted auth implementation; first remediation is now implemented on this branch. | P1 | S | `web/AGENTS.md`, `web/src/lib/api.ts` | Contributors could make security decisions from stale docs. | Keep auth docs and implementation together in future auth changes; add e2e coverage for login, refresh, and logout. |
| F-03 | Frontend API writes bypassed TanStack Query domain hooks; first remediation is now implemented on this branch. | P1 | M | `web/src/hooks/useImport.ts`, `web/src/hooks/useCsvImport.ts`, `web/src/hooks/useDiscover.ts`, `web/src/hooks/useRulesUrl.ts`, `web/src/hooks/usePlayerAids.ts` | Component-owned loading/error state fragments cache invalidation and makes mobile/offline behavior harder. | Keep API calls inside hooks; add component tests or e2e coverage for import, discover, rules URL, and player aids. |
| F-04 | `pkg/shared` docs appear stale or under-wired. ✅ RESOLVED | P2 | S | `README.md`, `AGENTS.md`, `services/api/AGENTS.md`, `docs/runbook/testing.md`, `docs/runbook/monitoring.md`, `infra/modules/monitoring/README.md`, `CLAUDE.md` | Docs say shared error/envelope/middleware live in `pkg/shared`, but the active API uses `internal` packages and `go.work` only includes `services/api`. | Removed all stale `pkg/shared` references from docs and AGENTS files. `pkg/shared/` does not exist on disk — `services/api/internal/apierr` and `services/api/internal/httpx` are the active packages. |
| F-05 | BGG sync runs synchronously inside HTTP request lifecycle. | P1 | L | `services/api/internal/importer/service.go`, `services/api/internal/importer/handler.go` | Large BGG collections can exceed user patience, Cloud Run timeouts, or mobile network stability. | Convert sync to background job: enqueue request, return job ID, expose job status/result endpoint. |
| F-06 | CSV parsing silently skips malformed rows. | P2 | M | `services/api/internal/importer/service.go`, `web/src/pages/ImportCsvPage.tsx` | Users cannot tell whether missing imported games were invalid rows, duplicate rows, BGG failures, or skipped parser errors. | Return row-level warnings with line number, original ID/name, and reason; render warnings in preview. |
| F-07 | API composition root will become a god file as domains grow. | P2 | M | `services/api/cmd/server/main.go` | Startup wiring is readable now, but adding more domains will make route/middleware/dependency wiring harder to review. | Extract `internal/app` or `internal/server` assembly: config, pool, handlers, routes, middleware, lifecycle. |
| F-08 | Error envelopes can expose wrapped bad-request/validation messages. | P2 | S | `services/api/internal/httpx/write.go` | Current policy is safe for unknown errors, but wrapped validation errors may accidentally include internal context. | Add public-safe error type or message sanitizer; keep detailed err in logs only. |
| F-09 | Readiness depends on JWKS reachability. | P2 | S | `services/api/cmd/server/main.go`, `services/api/internal/jwt/verifier.go` | Transient Supabase/JWKS issues can make otherwise serving instances fail readiness and churn. | Split `/readyz` into hard DB readiness and softer `/health/dependencies`; rely on verifier cache for serving. |
| F-10 | API CSP is extremely strict for all responses. | P3 | S | `services/api/internal/httpx/middleware.go` | Fine for JSON-only API, but future file/previews/assets will break unexpectedly. | Keep for JSON API; document it or scope headers by response type/path if API serves browser-rendered content. |

## Highest-impact sequence

1. Finish validating token-storage remediation in browser/e2e coverage.
2. Add browser/e2e coverage for login, refresh, and logout.
3. Add coverage for the new import/discover/rules/player-aid hooks.
4. ~~Decide whether `pkg/shared` is active or legacy.~~ ← DONE
5. Move BGG sync to async jobs.

## Technical notes

### F-01 token storage

Previous token helper read and wrote both tokens using `localStorage`.

That was the single most important flaw because refresh tokens extend the blast radius of XSS.

The target design now being implemented:
- Access token lives in memory only.
- Refresh token is set by API as `HttpOnly; Secure; SameSite=Lax` or `Strict` cookie.
- Refresh endpoint reads the cookie, not JSON body.
- Logout clears the cookie server-side.
- Auth context starts by calling a session/refresh endpoint instead of reading `localStorage`.

### F-03 frontend state consistency

`web/src/lib/api.ts` centralizes raw `fetch`, which is good.

The issue is not raw fetch sprawl.

The issue is component-level mutation and loading/error state sprawl.

Domain hooks should own server state and cache invalidation.

### F-05 async importer

A job-based sync would improve UX and reliability.

Minimum viable model:
- `POST /api/v1/import/sync` returns `{ job_id }` with `202 Accepted`.
- `GET /api/v1/import/jobs/{id}` returns status, counters, and errors.
- DB table stores user-owned jobs with status and timestamps.
- Worker can run in-process first, then graduate to Cloud Tasks/Pub/Sub later.

## Review commands used

```sh
rg --files -g 'AGENTS.md' -g 'README*' -g 'Makefile' -g 'go.work' -g 'package.json' -g 'src/**' -g 'services/**' -g 'docs/**'
rg -n "fetch\(" web/src
rg -n "useEffect|api\." web/src/pages web/src/components web/src/hooks
nl -ba services/api/cmd/server/main.go
nl -ba services/api/internal/catalog/store.go
nl -ba services/api/internal/httpx/write.go
nl -ba services/api/internal/httpx/middleware.go
nl -ba services/api/internal/importer/service.go
nl -ba web/src/lib/api.ts
nl -ba web/src/contexts/AuthContext.tsx
nl -ba web/src/hooks/useGame.ts
nl -ba web/src/hooks/useProfile.ts
nl -ba README.md
nl -ba go.work
```
