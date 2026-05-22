# mbgc-auth-service

Profile service. Delegates identity to Supabase and owns
mbgc-specific profile data: BGG username, admin flags.

## Stack

- **Language:** Go 1.25
- **Auth provider:** Supabase (JWT issued by Supabase, validated at gateway)
- **Shared:** `github.com/LuisMedinaG/mbgc/pkg/shared`

## Domain

- User profile (BGG username, admin flag)
- Lazy profile creation on first access (upsert pattern)

## API surface (mounted under `/api/v1/profile/*` at the gateway)

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/profile` | Current user profile (creates on first access) |
| `PUT` | `/api/v1/profile/bgg-username` | Update BGG username |

## Key env vars

| Var | Purpose |
|---|---|
| `DATABASE_URL` | Supabase Postgres connection string |
| `PORT` | Listen port (default 8001) |

## Commands

```sh
make dev
make test
make migrate-up   # apply migrations
make migrate-down # rollback migrations
```

## Deployment

GCP Cloud Run — deployed via GitHub Actions CI/CD.
Database URL injected as secret.

<claude-mem-context>
</claude-mem-context>
