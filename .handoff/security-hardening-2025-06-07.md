# Security Hardening Handoff — 2026-06-07

## What was done

Performed a security audit of the mbgc API against 7 common vulnerability categories and implemented the top 6 fixes (P0+P1+P2).

## Completed fixes

### P0-1: Removed TrustGatewayHeaders bypass
- **Risk:** Middleware existed at `pkg/shared/httpx/middleware.go` that would bypass JWT auth if accidentally wired into the middleware chain. Read `X-User-ID`, `X-Username`, `X-Is-Admin` from plain HTTP headers and inject them into context — an attacker could impersonate any user.
- **Fix:** Deleted the function + its 2 tests. `SetGatewayUser()` (used by JWT middleware) is kept — only the header-injection middleware was removed.
- **Files:** `pkg/shared/httpx/middleware.go`, `middleware_test.go`, `README.md`

### P0-2: Shared HTTP client with timeout
- **Risk:** `http.DefaultClient` has no timeout. A hung Supabase would exhaust goroutines (used in 6 places across auth handler + seed).
- **Fix:** Created `httpx.DefaultClient` with 10s timeout. Auth handler now accepts `*http.Client` in constructor. Seed uses `httpx.DefaultClient` directly.
- **Files:** `pkg/shared/httpx/client.go` (new), `services/api/internal/auth/handler.go`, `services/api/internal/seed/seed.go`, `services/api/cmd/server/main.go`

### P1-1: Rate limiter on auth endpoints
- **Risk:** No brute-force protection on `POST /auth/login` and `POST /auth/refresh`.
- **Fix:** Per-IP token bucket rate limiter (5 req/s, burst 10) on login/refresh/logout. Returns 429 via existing `apierr.ErrRateLimit` sentinel. Background cleanup every 5 min to prevent memory leaks.
- **Files:** `pkg/shared/httpx/rate_limiter.go` (new), `services/api/internal/auth/handler.go` (RegisterRoutes now takes `rateLimit` param), `services/api/cmd/server/main.go`
- **Deps:** Promoted `golang.org/x/time` to direct dependency in `pkg/shared/go.mod`

### P1-2: Request body size limit
- **Risk:** No limit on JSON body size — memory exhaustion DoS possible.
- **Fix:** `LimitBodySize(1MB)` middleware applied globally. Uses `http.MaxBytesReader`.
- **Files:** `pkg/shared/httpx/body_limit.go` (new), `services/api/cmd/server/main.go`

### P2: Search/filter string caps
- **Risk:** Unbounded search/category strings accepted as input.
- **Fix:** `truncate(s, 255)` applied to search and category query params in game handler.
- **Files:** `services/api/internal/game/handler.go`

## New ACID references in code

| ACID | What | Where |
|---|---|---|
| `api-layer.SEC.1` | Shared HTTP client timeout | `pkg/shared/httpx/client.go:12` |
| `api-layer.SEC.2` | Rate limit auth endpoints | `pkg/shared/httpx/rate_limiter.go:21`, `services/api/cmd/server/main.go:117` |
| `api-layer.SEC.3` | Body size limit | `pkg/shared/httpx/body_limit.go:10`, `services/api/cmd/server/main.go:144` |
| `api-layer.SEC.4` | Search/filter length caps | `services/api/internal/game/handler.go:237` |

These ACIDs are defined in `features/api-layer.feature.yaml` under `constraints.SEC`.

## Changed constructor signatures

- `auth.NewHandler(store, supabaseURL, apiKey)` → `auth.NewHandler(store, supabaseURL, apiKey, client)`
- `auth.RegisterRoutes(mux, auth)` → `auth.RegisterRoutes(mux, auth, rateLimit)`
- Tests updated: `services/api/internal/auth/handler_test.go` — all calls now pass `http.DefaultClient` as 4th arg

## New middleware in httpx package

- `httpx.DefaultClient` — `*http.Client` with 10s timeout
- `httpx.RateLimiter(ratePerSec, burst)` — per-IP token bucket middleware
- `httpx.LimitBodySize(maxBytes)` — body size cap middleware

## ACID references to push

```sh
# Prerequisite: ACAI_API_TOKEN must be in root .env (not services/api/.env)
# cp services/api/.env .env  # if token exists there

npx @acai.sh/cli push --all
npx @acai.sh/cli set-status --product mbgc --impl dev '{
  "api-layer.SEC.1":{"status":"completed"},
  "api-layer.SEC.2":{"status":"completed"},
  "api-layer.SEC.3":{"status":"completed"},
  "api-layer.SEC.4":{"status":"completed"}
}'
npx @acai.sh/cli push --all
```

## Remaining backlog (P3, not implemented)

| Priority | Task | Effort |
|---|---|---|
| P3 | Monitoring/error tracking (Sentry free tier or Cloud Run error alerting) | 2-4h |
| P3 | Dependabot config for Go + JS vulnerability scanning | 30min |
| P3 | Content-Type enforcement on JSON handlers | 15min |
| P4 | Secrets hardening (pre-commit hook for credential patterns in .env files) | 1h |
| P4 | `http.Client` timeout also in BGG importer client | 30min |

## Verification

- `make test-v` (services/api): all tests pass with `-race`
- `go test -v -race ./...` (pkg/shared): all tests pass
- `go vet ./...` (services/api): clean
- `make lint`: clean (pre-existing `tflint` plugin issue in infra/ is unrelated)

## To sync docs

AGENTS.md has already been updated with the new middleware + conventions. The next agent should:

1. **Load and run `/sync-docs` skill** — verify AGENTS.md is current and update the per-service CLAUDE.md files (`services/api/CLAUDE.md`, `pkg/shared/CLAUDE.md`) with new middleware entries and HTTP client convention.

2. **Push acai** — run the commands above. Delete this handoff file after completing both steps:
   ```sh
   rm .handoff/security-hardening-2025-06-07.md
   ```
