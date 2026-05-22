# mbgc-auth-service

Profile service for mbgc. Authentication (login/signup/sessions/tokens) is handled by **Supabase Auth** — this service manages the application-level profile data that Supabase doesn't own.

## What this service owns

- `profile.users` — BGG username, admin flag
- Profile CRUD routes

## Routes

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/profile` | Get current user profile |
| `PUT` | `/api/v1/profile/bgg-username` | Update BGG username |
| `GET` | `/healthz` | Health check |

All routes except `/healthz` expect `X-User-ID` header injected by the gateway.

## Architecture

```
cmd/server/main.go          ← server setup, wiring
internal/
  config/config.go          ← env vars
  handler/handler.go        ← HTTP layer (thin)
  service/service.go        ← business logic
  store/store.go            ← SQL (pgx)
  model/model.go            ← domain types
migrations/
  001_init.up.sql           ← profile schema
  001_init.down.sql
deploy/
  Dockerfile
  fly.toml
```

## Environment variables

| Var | Required | Default | Description |
|-----|----------|---------|-------------|
| `DATABASE_URL` | yes | — | Supabase Postgres connection string |
| `PORT` | no | `8001` | Listen port |

## Setup

```sh
cp .env.example .env
make migrate-up    # run against your Supabase DB
make dev
```
