@AGENTS.md

# mbgc — Monorepo

Personal board game collection app. Consolidated Go API + React frontend.

## Directory Structure

```
mbgc/
├── services/
│   └── api/             Single consolidated Go API (auth, games, collections, importer, profile)
├── web/                 React + Vite + TypeScript + Tailwind
├── ios/                 SwiftUI iOS app — LOCAL-FIRST, no backend (Swift 6.2, SwiftData)
│   ├── AGENTS.md        iOS architecture, data model, dead code map, next steps
│   └── MBGC/
│       ├── Models/      Game.swift, Collection.swift (SwiftData @Model)
│       └── Networking/  BGGClient.swift, BGGXMLParser.swift, APIClient.swift (dead)
├── docs/
│   └── handoff/
│       └── 2026-06-25-ios-local-first.md   Full iOS migration log (Sessions 1–3)
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
  /readyz                health check
```

JWT validation is inline in `services/api/internal/jwt/` — no gateway proxy.

```
iOS app  (local-first — does NOT call services/api)
      │
      ├──▶  BGG XML API (public, no auth)
      │       https://boardgamegeek.com/xmlapi2/thing?id=...&stats=1
      │       BGGClient actor — 2 RPS, 4-attempt retry, batch 20
      │
      └──▶  SwiftData (on-device SQLite)
              Models: Game (@bggId unique), Collection (Library seeded on first launch)
```

**iOS architecture changed 2026-06-25** — login removed, no JWT, no backend calls.
Full log: `docs/handoff/2026-06-25-ios-local-first.md`. Agent rules: `ios/AGENTS.md`.

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
