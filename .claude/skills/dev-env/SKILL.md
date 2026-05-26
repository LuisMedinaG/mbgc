---
name: dev-env
description: Start the full local development environment (Supabase + all services + web). Use when asked to start dev, bring up the stack, or set up local environment.
---

# Local Dev Environment

## First-time setup

```sh
# 1. Copy env files for each service (once per machine)
for svc in gateway auth game importer; do
  cp services/$svc/.env.example services/$svc/.env
done
cp web/.env.example web/.env

# 2. Start local Supabase stack
supabase start
# Outputs: API URL, anon key, JWT secret, DB URL — copy into service .env files

# 3. Run migrations for each service
for svc in auth game importer; do
  make -C services/$svc migrate-up
done
```

## Daily startup

```sh
supabase start          # if not already running
make dev-all            # starts all services + web in tmux (detach: ctrl+b d)
```

## Local service URLs

| Service | URL |
|---------|-----|
| web (Vite) | http://localhost:5173 |
| gateway | http://localhost:8000 |
| auth | http://localhost:8001 |
| game | http://localhost:8002 |
| importer | http://localhost:8003 |
| Supabase Studio | http://127.0.0.1:54323 |
| Supabase Auth | http://127.0.0.1:54321 |
| Supabase DB | postgresql://postgres:postgres@127.0.0.1:54322/postgres |

## Local .env values (from `supabase status`)

```
SUPABASE_URL=http://127.0.0.1:54321
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres
SUPABASE_JWT_SECRET=    # leave empty — local issues ES256, JWKS-only works
```

## Per-service dev

```sh
cd services/<name> && make dev    # runs with hot-reload via air or go run
```

## Stopping

```sh
supabase stop           # preserves data
# or
supabase stop --no-backup  # full reset
```

## Switching to remote Supabase

```sh
# In each service .env: swap local URLs for remote
SUPABASE_URL=https://mlltpfszhtxhphoaeydh.supabase.co
DATABASE_URL=postgresql://postgres.<ref>:<pw>@aws-0-us-west-2.pooler.supabase.com:5432/postgres
```

**Never run `supabase db push` without explicit confirmation** — it writes to production.
