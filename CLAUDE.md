@AGENTS.md

# mbgc — Monorepo

Personal board game collection app. Consolidated Go API + React frontend.

## Directory Structure

```
mbgc/
├── pkg/shared/          Go shared library (envelope, apierr, httpx)
├── services/
│   └── api/             Single consolidated Go API (auth, games, collections, importer, profile)
├── web/                 React + Vite + TypeScript + Tailwind
├── infra/               Terraform — GCP Cloud Run, Cloudflare, Supabase
│   └── scripts/
│       ├── bootstrap.sh       one-time infra provisioning + GitHub secrets sync
│       └── rotate-secrets.sh  secret rotation (cloudflare | supabase | api | all)
├── scripts/             Operational scripts (admin user provisioning)
└── SETUP.md             Canonical first-time setup guide (local + prod)
```

## Request Flow

```
Browser / web
      │
      ▼
services/api  (JWT validation via JWKS + all route handlers)
  /api/v1/auth/*         auth ping
  /api/v1/profile/*      user profile, BGG username
  /api/v1/games/*        games, collections, player aids
  /api/v1/collections/*  vibes/collections CRUD
  /api/v1/import/*       BGG sync, CSV import
  /healthz               health check
```

JWT validation is inline in `services/api/internal/jwt/` — no gateway proxy.

## CI/CD

- **CI** — `.github/workflows/ci.yml`: build + test + vet, web lint/build, infra lint
- **Deploy** — `.github/workflows/deploy.yml`: deploys `services/api` on push to `main`
- **Infra** — `.github/workflows/infra.yml`: `terraform plan` on PR, `terraform apply` on merge to `main`
- **Secrets** — `infra/scripts/bootstrap.sh` provisions infra + syncs secrets to GitHub Actions
- **Rotation** — `make rotate-secrets` or `infra/scripts/rotate-secrets.sh` to rotate any secret group

## Infrastructure

- **GCP Cloud Run** — `mbgc-api` single service (`services/api`)
- **Cloudflare** — Pages frontend, DNS for `lumedina.dev` (see [docs/runbook/cloudflare/](docs/runbook/cloudflare/))
- **Supabase** — auth provider + Postgres (migrations in `services/api/migrations/`)
- **Terraform** — `infra/` is the single source of truth (no Fly.io)
