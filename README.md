# mbgc — My Board Game Collection

Personal board game collection app with BoardGameGeek integration. Track games, organize collections, sync from BGG.

```
web (React + Vite)  →  services/api (Go)  →  Supabase Postgres
  Cloudflare Pages       api.lumedina.dev       GCP Cloud Run

iOS app (SwiftUI)   →  BGG XML API (public, no auth)
  SwiftData local        boardgamegeek.com/xmlapi2
```

> **iOS is local-first.** The iOS app does not call `services/api`. It reads game
> metadata directly from BGG's public XML API and stores everything on-device in SwiftData.
> See [ios/AGENTS.md](./ios/AGENTS.md) and [docs/handoff/2026-06-25-ios-local-first.md](./docs/handoff/2026-06-25-ios-local-first.md).

## Quick Start

```sh
git clone https://github.com/LuisMedinaG/mbgc.git && cd mbgc
make setup-local   # copies .env, starts Supabase, runs migrations
make dev           # API :8080 + web :5173 in tmux
```

→ Full guide: **[SETUP.md](./SETUP.md)**

## Prerequisites

| Tool | For | Install |
|---|---|---|
| Go 1.25+ | API | `brew install go` |
| Bun | Web | `curl -fsSL https://bun.sh/install \| bash` |
| Supabase CLI | DB | `brew install supabase/tap/supabase` |
| tmux | Dev | `brew install tmux` |
| golang-migrate | DB | `brew install golang-migrate` |
| psql (optional) | DB | `brew install libpq && brew link --force libpq` |
| gcloud (prod) | Infra | `brew install --cask google-cloud-sdk` |
| Terraform (infra) | Infra | `brew install terraform` |
| Xcode 16+ | iOS | Mac App Store |
| XcodeGen | iOS | `brew install xcodegen` |

## Commands

```sh
# Web + API development
make dev             # start API + web in tmux (session: mbgc)
make db-migrate      # apply pending migrations
make db-reset        # wipe + replay local DB (local only)

# Build & test
make build           # build API + web
make test            # Go unit tests
make lint            # Go + web + infra lint
bash scripts/e2e-smoke.sh   # smoke test against running API

# iOS
cd ios && xcodegen generate   # regenerate .xcodeproj after adding Swift files
# then build/test via Xcode or xcodebuild (see ios/AGENTS.md)

# Secrets
make rotate-secrets          # rotate any secret group (interactive)
make rotate-secrets api      # just BGG token / service role key

# Infra
cd infra/environments/prod && terraform plan && terraform apply

# Acai specs
make acai-features   # list all features + completion status
make acai-push       # sync specs + refs to dashboard
```

## Architecture

| Component | Path | Role |
|---|---|---|
| Go API | `services/api` | JWT validation, all business logic, BGG sync |
| React SPA | `web` | Frontend — talks only to `services/api` |
| iOS app | `ios` | SwiftUI — **local-first**, talks only to BGG XML API |
| Shared lib | `services/api/internal` | Error types (`apierr`), response envelope, HTTP middleware (`httpx`) |
| Infrastructure | `infra` | Terraform — GCP, Cloudflare, Supabase |

**Web auth:** Supabase issues JWTs → API validates via JWKS on every request → identity in context.

**iOS auth:** none. No login, no JWT. Game data sourced from BGG's public XML API, stored on-device in SwiftData. `services/api` is not reachable from the iOS app.

**Admin user:** set `SEED_ADMIN_EMAIL` + `SEED_ADMIN_PASSWORD` + `SUPABASE_SERVICE_ROLE_KEY` in `.env` — created automatically on first boot, idempotent.

## Features

| Feature | Reqs | Done |
|---|---|---|
| api-layer | 35 | **35** (100%) |
| auth | 31 | **31** (100%) |
| profile | 19 | **15** (79%) |
| importer | 28 | **13** (46%) |
| game-detail | 33 | **5** (15%) |
| collection | 26 | **0** (0%) |
| vibes | 19 | **0** (0%) |

Spec-driven via [acai.sh](https://acai.sh) — `features/*.feature.yaml`.

## CI/CD

| Workflow | Trigger | Action |
|---|---|---|
| `ci.yml` | PR / push to dev | Build + test + lint |
| `deploy.yml` | Push to main | Deploy changed services |
| `infra.yml` | PR / merge to main | Terraform plan / apply |

GCP auth uses **Workload Identity Federation** — no long-lived keys committed.

## Docs

- [SETUP.md](./SETUP.md) — first-time setup (local + prod), admin user, migrations
- [docs/deployment.md](./docs/deployment.md) — GitHub secrets, Cloud Run env vars, Terraform details
- [docs/troubleshooting.md](./docs/troubleshooting.md) — common errors and fixes
- [docs/runbook/](./docs/runbook/) — categorized issue database; search with `rg "error text" docs/runbook/`
- [ios/AGENTS.md](./ios/AGENTS.md) — iOS architecture, data model, what works, what's dead code
- [docs/handoff/2026-06-25-ios-local-first.md](./docs/handoff/2026-06-25-ios-local-first.md) — full iOS local-first migration log (Sessions 1–3)

## Contributing

Branch from `dev` using `feature/*`, `fix/*`, `chore/*`, or `refactor/*`.
All PRs target `dev` — direct push to `main` is blocked.
Run `make test` and `bash scripts/e2e-smoke.sh` before opening a PR.

See [AGENTS.md](./AGENTS.md) for full contributor rules.

---

## License

Private — personal project.
