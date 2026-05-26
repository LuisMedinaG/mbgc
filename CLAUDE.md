@AGENTS.md

# mbgc — Monorepo

Personal board game collection app. Go microservices + React frontend.

## Directory Structure

```
mbgc/
├── pkg/shared/          Go shared library (envelope, apierr, httpx)
├── services/
│   ├── gateway/         JWT validation, reverse proxy
│   ├── auth/            User profiles, BGG username, admin roles
│   ├── game/            Games, collections, player aids
│   ├── importer/        BGG sync + CSV import
│   └── monolith/        [DEPRECATED] SQLite monolith — being decommissioned
├── web/                 React + Vite + TypeScript + Tailwind
└── infra/               Terraform — GCP Cloud Run, Cloudflare, Supabase
```

## Request Flow

```
Browser / web
      │
      ▼
services/gateway  (validates JWT → injects X-User-ID, X-Is-Admin)
      ├──▶ services/auth      /api/v1/auth/*  /api/v1/profile/*
      ├──▶ services/game      /api/v1/games/* /api/v1/collections/*
      └──▶ services/importer  /api/v1/import/*
```

Monolith runs independently on Fly.io, not behind the gateway.

## CI/CD

- **CI** — `.github/workflows/ci.yml`: build + test + vet all Go services, web lint/build, infra lint
- **Deploy** — `.github/workflows/deploy.yml`: deploys only changed services on push to `main`
- **Secrets** — `infra/scripts/bootstrap.sh` syncs GCP/Cloudflare credentials → GitHub Actions secrets

## Infrastructure

- **GCP Cloud Run** — all Go microservices
- **Fly.io** — monolith only (being decommissioned)
- **Cloudflare Pages** — `web/` frontend
- **Supabase** — auth provider + Postgres
- **Terraform** — `infra/` is the single source of truth
