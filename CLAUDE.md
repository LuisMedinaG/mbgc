@AGENTS.md

# mbgc — Monorepo

Personal board game collection app. Go microservices + React frontend.
Single git repo — one commit spans all services.

## Directory Structure

```
mbgc/
├── pkg/shared/          Go shared library (envelope, apierr, httpx)
├── services/
│   ├── gateway/         API gateway — JWT validation, reverse proxy
│   ├── auth/            Profile service — BGG username, admin roles
│   ├── game/            Core domain — games, collections, player aids
│   ├── importer/        BGG sync + CSV import
│   └── monolith/        [DEPRECATED] Original Go monolith — being replaced
├── web/                 React frontend (Vite + TypeScript + Tailwind)
├── infra/               Terraform IaC — GCP Cloud Run, Cloudflare, Supabase
```

## Request Flow

```
Browser / web
      │
      ▼
services/gateway  (validates JWT, routes by path prefix)
      ├──▶ services/auth      /api/v1/auth/*  /api/v1/profile/*
      ├──▶ services/game      /api/v1/games/* /api/v1/collections/*
      └──▶ services/importer  /api/v1/import/*
```

The monolith (`services/monolith`) runs independently on Fly.io and is not behind the gateway.
It is being decommissioned as microservices reach feature parity.

## Shared Conventions

- **Language:** Go 1.25 (services) · TypeScript / React (web)
- **Auth:** JWT — access tokens (15 min), refresh tokens (30 day)
- **Response envelope:** `{ "data": ... }` success · `{ "error": { "code": "...", "message": "..." } }` failure
- **Pagination:** `{ "data": [...], "meta": { "page": 1, "limit": 20, "total": N } }`
- **Errors:** sentinel errors in `pkg/shared/apierr` — never leak raw DB errors to clients
- **DB:** SQLite in monolith; Postgres via Supabase in microservices

## Development

```sh
make dev-all                    # Start all services + web in tmux (detach: ctrl+b d)

# Per-service (run from service directory)
cd services/gateway && make dev        # go run ./cmd/server, loads .env
cd services/gateway && make test-v    # go test -v -race ./...
cd services/gateway && make build     # produces ./server binary
cd services/gateway && make tidy      # go mod tidy

# Web (from web/)
make dev       # Vite dev server
make build     # tsc -b && vite build
make lint
make test-e2e  # Playwright e2e (requires full stack)
```

## CI/CD

- **CI** — `.github/workflows/ci.yml`: Build, test, vet all Go services + web lint/build + infra lint
- **Deploy** — `.github/workflows/deploy.yml`: Deploys only changed services on push to `main`
- **Secrets** — Managed via `infra/scripts/bootstrap.sh`; syncs GCP/Cloudflare credentials to GitHub Actions secrets

## Branching Strategy

```
feature/*  →  dev  →  staging  →  main
```

Promotion: `dev → staging` and `staging → main` require PRs.
Direct push to `main`/staging` is blocked (admin bypass exists for emergencies).

## Infrastructure

- **GCP Cloud Run** — all Go microservices (deployed via each service's CI/CD)
- **Fly.io** — monolith only (being decommissioned)
- **Cloudflare Pages** — `web/` frontend
- **Supabase** — auth provider + Postgres for microservices
- **Terraform** — `infra/` is the single source of truth for all cloud resources

<claude-mem-context>
</claude-mem-context>
