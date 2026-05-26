# mbgc-gateway

API gateway — the single ingress point for all mbgc microservice traffic.
Validates JWTs so downstream services can trust the forwarded identity.

## Stack

- **Language:** Go 1.25
- **Auth:** `github.com/golang-jwt/jwt/v5` + `github.com/MicahParks/keyfunc/v3` — validates `Authorization: Bearer` tokens
- **Shared:** `github.com/LuisMedinaG/mbgc/pkg/shared` (middleware, envelope)

## JWT verification

- **Primary path — ES256/RS256 via JWKS.** Supabase signs access tokens with a
  private key it never shares; the gateway fetches only the *public* keys from
  `${SUPABASE_URL}/auth/v1/.well-known/jwks.json` (auto-refreshed, key rotation
  handled by `keyfunc`). A leaked public key cannot forge tokens.
- **Legacy path — HS256 (optional).** Enabled only when `SUPABASE_JWT_SECRET` is
  set, to keep verifying tokens minted before the migration to JWT signing keys.
  Symmetric: the secret can both verify *and* mint tokens, so prefer JWKS-only.
- **Validated on every token:** signature, `exp` (required), `iss` =
  `${SUPABASE_URL}/auth/v1`, and `aud` = `authenticated`. anon/service_role API
  keys are rejected as user bearer tokens.
- **Config:** `SUPABASE_URL` is required; `SUPABASE_JWT_SECRET` is optional.

## Routing table

| Prefix | Upstream service |
|---|---|
| `/api/v1/auth/*` | services/auth |
| `/api/v1/profile/*` | services/auth |
| `/api/v1/games/*` | services/game |
| `/api/v1/collections/*` | services/game |
| `/api/v1/discover` | services/game |
| `/api/v1/import/*` | services/importer |

## Responsibilities

- Validate JWT on every request; return `401` if invalid/missing
- Forward `X-User-ID`, `X-Username`, `X-Is-Admin` headers to upstream services (extracted from JWT claims)
- CORS — allow `mbgc-web` origin
- Health check at `/healthz`

## What the gateway does NOT do

- Business logic
- Database access
- Token issuance (that is services/auth)

## Commands

```sh
make dev    # go run ./cmd/server
make build  # outputs ./server binary
make test
```

## Deployment

GCP Cloud Run — deployed via GitHub Actions CI/CD.
`SUPABASE_URL` injected via env var (drives JWKS verification).
`SUPABASE_JWT_SECRET` is optional — set only for legacy HS256 fallback.

<claude-mem-context>
</claude-mem-context>
