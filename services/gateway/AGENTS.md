# AGENTS.md — services/gateway

API gateway: single ingress point. Validates JWTs and reverse-proxies to upstream services. No business logic, no DB.

## Stack

- **Language:** Go 1.25
- **Auth:** `github.com/golang-jwt/jwt/v5` + `github.com/MicahParks/keyfunc/v3`
- **Shared:** `github.com/LuisMedinaG/mbgc/pkg/shared`
- **Deployment:** GCP Cloud Run — `SUPABASE_URL` required; `SUPABASE_JWT_SECRET` optional

## JWT verification

- **Primary — ES256/RS256 via JWKS:** fetches public keys from `${SUPABASE_URL}/auth/v1/.well-known/jwks.json`; auto-refreshed + key rotation via `keyfunc`. Leaked public key cannot forge tokens.
- **Legacy — HS256:** enabled only when `SUPABASE_JWT_SECRET` is set (tokens minted before JWKS migration). Symmetric — prefer JWKS-only.
- **Validated on every token:** signature, `exp`, `iss` = `${SUPABASE_URL}/auth/v1`, `aud` = `authenticated`. anon/service_role keys are rejected.

## Routing table

| Prefix | Upstream |
|---|---|
| `/api/v1/auth/*` | services/auth |
| `/api/v1/profile/*` | services/auth |
| `/api/v1/games/*` | services/game |
| `/api/v1/collections/*` | services/game |
| `/api/v1/discover` | services/game |
| `/api/v1/import/*` | services/importer |

Health check: `GET /healthz` (no auth).

## Commands

```sh
make dev      # go run ./cmd/server; loads .env; listens on :8000
make test-v   # go test -v -race ./...
make lint     # go vet ./...
```

## Adding a route

1. Add prefix → upstream URL mapping in `cmd/server/main.go`
2. Update the routing table above
3. The gateway extracts JWT claims and forwards `X-User-ID`, `X-Username`, `X-Is-Admin` — upstream services call `httpx.UserIDFromContext` to read these; they never re-validate the token

## Boundaries

**Never:**
- Add business logic or DB access
- Issue or refresh tokens (that is Supabase / services/auth)
- Create pass-through routes that skip JWT validation
- Add CORS headers in upstream services — CORS is configured here only

**Ask first:**
- Changing JWT validation logic or the forwarded header names (all downstream services depend on them)
- Adding a new public (unauthenticated) endpoint
