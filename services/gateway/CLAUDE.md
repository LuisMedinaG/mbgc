# mbgc-gateway

API gateway — the single ingress point for all mbgc microservice traffic.
Validates JWTs so downstream services can trust the forwarded identity.

## Stack

- **Language:** Go 1.25
- **Auth:** `github.com/golang-jwt/jwt/v5` — validates `Authorization: Bearer` tokens
- **Shared:** `github.com/LuisMedinaG/mbgc/pkg/shared` (middleware, envelope)

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
JWT secret injected via `SUPABASE_JWT_SECRET` env var.

<claude-mem-context>
</claude-mem-context>
