# mbgc — My Board Game Collection

Personal board game collection app with BoardGameGeek integration. Track games, organize vibes, sync from BGG.

```
web (React + Vite)  →  services/api (Go)  →  Supabase Postgres
  Cloudflare Pages       api.lumedina.dev       GCP Cloud Run
```

## Quick Start

```sh
git clone https://github.com/LuisMedinaG/mbgc.git && cd mbgc
make setup-local   # copies .env, starts Supabase, runs migrations
make dev           # API :8080 + web :5173 in tmux
```

→ Full guide: **[SETUP.md](./SETUP.md)**

## Prerequisites

| Tool | Install |
|---|---|
| Go 1.25+ | `brew install go` |
| Bun | `curl -fsSL https://bun.sh/install \| bash` |
| Supabase CLI | `brew install supabase/tap/supabase` |
| tmux | `brew install tmux` |
| golang-migrate | `brew install golang-migrate` |
| psql (optional) | `brew install libpq && brew link --force libpq` |
| gcloud (prod) | `brew install --cask google-cloud-sdk` |
| Terraform (infra) | `brew install terraform` |

## Commands

```sh
# Development
make dev             # start API + web in tmux (session: mbgc)
make db-migrate      # apply pending migrations
make db-reset        # wipe + replay local DB (local only)

# Build & test
make build           # build API + web
make test            # Go unit tests
make lint            # Go + web + infra lint
bash scripts/e2e-smoke.sh   # smoke test against running API

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
| Go API | `services/api` | JWT validation, all business logic |
| React SPA | `web` | Frontend, talks only to `services/api` |
| Shared lib | `pkg/shared` | Error types, response envelope, HTTP middleware |
| Infrastructure | `infra` | Terraform — GCP, Cloudflare, Supabase |

**Auth:** Supabase issues JWTs → API validates via JWKS on every request → identity in context.

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

## Contributing

Branch from `dev` using `feature/*`, `fix/*`, `chore/*`, or `refactor/*`.
All PRs target `dev` — direct push to `main` is blocked.
Run `make test` and `bash scripts/e2e-smoke.sh` before opening a PR.

See [AGENTS.md](./AGENTS.md) for full contributor rules.

---

## License

Private — personal project.
