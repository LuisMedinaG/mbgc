# AGENTS.md — services/auth

Profile service. Supabase owns identity (JWT issuance, login, refresh, logout). This service owns mbgc-specific profile data: BGG username, admin flag.

## Stack

- **Language:** Go 1.25
- **Auth provider:** Supabase (JWT issued by Supabase, validated at gateway)
- **Shared:** `github.com/LuisMedinaG/mbgc/pkg/shared`
- **Deployment:** GCP Cloud Run — `DATABASE_URL` injected as secret

## API surface (mounted under `/api/v1/profile/*` at gateway)

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/profile` | Current user profile (creates on first access) |
| `PUT` | `/api/v1/profile/bgg-username` | Update BGG username |

## Env vars

| Var | Purpose |
|---|---|
| `DATABASE_URL` | Supabase Postgres connection string |
| `PORT` | Listen port (default 8001) |

## Commands

```sh
make dev          # loads .env; listens on :8001
make test-v       # go test -v -race ./...
make migrate-up   # apply Postgres migrations
make migrate-down
```

## Patterns

- **Lazy upsert:** Profile is created on first `GET /profile` — use `INSERT ... ON CONFLICT DO UPDATE`, not a separate create endpoint
- Get caller identity via `httpx.UserIDFromContext(r.Context())` — the gateway already validated the JWT and injected headers
- No password or session logic here — all auth flows (login, refresh, logout) are handled by Supabase directly

## Boundaries

**Never:**
- Issue, validate, or refresh JWTs
- Duplicate Supabase auth endpoints

**Ask first:**
- Changes to the profile schema (the gateway JWT claims and downstream services depend on stable user identity)
- Adding admin-assignment logic (security-sensitive)
