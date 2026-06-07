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
  /readyz               health check
```

JWT validation is inline in `services/api/internal/jwt/` — no gateway proxy.

## CI/CD

- **Pipeline** — `.github/workflows/pipeline.yml`: single workflow for all CI + deploy. PR → CI only. Push to dev → CI + deploy API (dev). Push to main → CI + deploy API (prod, requires manual approval via `production` environment gate) + deploy web. Go tests run with `-race` and `-coverprofile`; coverage artifacts uploaded + per-function summary posted to PR step summary. CI fails if `services/api` coverage drops below 50%.
- **Infra** — `.github/workflows/infra.yml`: `terraform plan` on PR to main (posts plan as PR comment via dynamic path), `terraform apply` on merge to main (infra/ changes only)
- **E2E** — `.github/workflows/e2e.yml`: manual Playwright tests (workflow_dispatch)
- **Reusable** — `.github/workflows/deploy-cloud-run.yml`: Cloud Run build + deploy, called by pipeline.yml. No migration step in CI — migrations run automatically at server startup via golang-migrate (SQL embedded in binary, tracked in `schema_migrations` table).
- **Secrets** — `infra/scripts/bootstrap.sh` provisions infra + syncs secrets to GitHub Actions
- **Rotation** — `make rotate-secrets` or `infra/scripts/rotate-secrets.sh` to rotate any secret group
- **Runbook** — `docs/runbook/ci-cd/_index.md`: full secrets list, failure diagnosis, manual deploy steps

## Infrastructure

- **GCP Cloud Run** — `mbgc-api` single service (`services/api`)
- **Cloudflare** — Pages frontend, DNS for `lumedina.dev` (see [docs/runbook/cloudflare/](docs/runbook/cloudflare/))
- **Supabase** — auth provider + Postgres (migrations in `services/api/migrations/`)
- **Terraform** — `infra/` is the single source of truth (no Fly.io)
