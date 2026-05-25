# mbgc — My Board Game Collection

A personal board game collection app with BoardGameGeek (BGG) integration. Track games, organize collections, sync from BGG, and more.

**Live:** https://lumedina.dev (frontend) · https://api.lumedina.dev (API)

---

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Setup](#setup)
  - [1. Clone the repo](#1-clone-the-repo)
  - [2. Install tooling](#2-install-tooling)
  - [3. Get Supabase credentials](#3-get-supabase-credentials)
  - [4. Get BGG credentials (optional)](#4-get-bgg-credentials-optional)
  - [5. Configure local `.env` files](#5-configure-local-env-files)
- [Local Development](#local-development)
- [Testing](#testing)
- [Deployment](#deployment)
- [GitHub Secrets Setup](#github-secrets-setup)
- [Troubleshooting](#troubleshooting)
- [Project Layout](#project-layout)
- [Contributing](#contributing)

---

## Architecture

Five Go microservices behind a single API gateway, plus a React frontend. The original monolith is being decommissioned.

```
                    ┌─────────────────────────┐
                    │   web (React + Vite)    │   :5173 dev / Cloudflare Pages prod
                    └───────────┬─────────────┘
                                │
                                ▼
                    ┌─────────────────────────┐
                    │  gateway (JWT + CORS)   │   :8000  → api.lumedina.dev
                    └─┬─────────┬─────────┬───┘
                      │         │         │
              ┌───────▼──┐ ┌────▼────┐ ┌──▼───────┐
              │   auth   │ │  game   │ │ importer │
              │  :8001   │ │  :8002  │ │  :8003   │
              └───────┬──┘ └────┬────┘ └──┬───────┘
                      │         │         │
                      └─────────▼─────────┘
                          Supabase Postgres
                          (auth, games, importer schemas)
```

| Service | Path | Responsibility |
|---|---|---|
| `web` | React SPA | UI, talks only to gateway |
| `services/gateway` | Go | JWT validation, reverse proxy, CORS |
| `services/auth` | Go | User profile (BGG username, admin flag) |
| `services/game` | Go | Games, collections, player aids |
| `services/importer` | Go | BGG sync + CSV import |
| `services/monolith` | Go | **[DEPRECATED]** Original SQLite app |
| `pkg/shared` | Go library | Response envelope, errors, HTTP middleware |
| `infra` | Terraform | GCP Cloud Run + Cloudflare + Supabase |

**Auth flow:** Supabase issues JWTs → gateway validates → forwards `X-User-ID` / `X-Username` / `X-Is-Admin` headers to upstream services. Internal services trust these headers and never re-validate the JWT.

---

## Prerequisites

| Tool | Version | macOS install |
|---|---|---|
| Go | 1.25+ | `brew install go` |
| Bun | 1.3+ | `curl -fsSL https://bun.sh/install \| bash` |
| tmux | any | `brew install tmux` |
| gcloud CLI | latest | `brew install --cask google-cloud-sdk` |
| GitHub CLI | latest | `brew install gh` |
| Terraform | 1.14+ | `brew install terraform` (only needed for infra changes) |
| Docker | latest | `brew install --cask docker` (only needed for builds) |
| psql | any | `brew install libpq && brew link --force libpq` (for migrations) |

**Verify:**
```sh
go version          # go version go1.25.x
bun --version       # 1.3.12+
tmux -V             # tmux 3.x
gcloud --version    # Google Cloud SDK
gh auth status      # Logged in
```

---

## Quick Start

If you already have all secrets configured, this is the fast path:

```sh
git clone https://github.com/LuisMedinaG/mbgc.git
cd mbgc

# Copy env templates and fill in secrets (see Setup → step 5)
cp services/gateway/.env.example services/gateway/.env
cp services/auth/.env.example     services/auth/.env
cp services/game/.env.example     services/game/.env
cp services/importer/.env.example services/importer/.env
cp web/.env.example               web/.env

# Open all .env files to fill in secrets
$EDITOR services/gateway/.env services/auth/.env services/game/.env services/importer/.env web/.env

# Install web deps
cd web && bun install && cd ..

# Start everything (tmux session named 'mbgc')
make dev-all

# Attach to tmux to watch logs
tmux attach -t mbgc

# In another terminal — run smoke tests
bash scripts/e2e-smoke.sh
```

If you do not have secrets yet, see [Setup](#setup).

---

## Setup

### 1. Clone the repo

```sh
git clone https://github.com/LuisMedinaG/mbgc.git
cd mbgc
```

### 2. Install tooling

See [Prerequisites](#prerequisites). On a fresh macOS:

```sh
brew install go bun tmux gh terraform libpq
brew install --cask google-cloud-sdk docker
brew link --force libpq

# Authenticate
gh auth login
gcloud auth application-default login
```

### 3. Get Supabase credentials

You need **two values** from Supabase: `SUPABASE_JWT_SECRET` and `DATABASE_URL`.

**Project URL:** https://supabase.com/dashboard/project/mlltpfszhtxhphoaeydh

#### `SUPABASE_JWT_SECRET`

1. Open: https://supabase.com/dashboard/project/mlltpfszhtxhphoaeydh/settings/jwt
2. Scroll to **JWT Secret**
3. Click **Reveal** and copy the value
4. Looks like: `super-secret-jwt-token-with-at-least-32-characters-long`

#### `DATABASE_URL`

1. Open: https://supabase.com/dashboard/project/mlltpfszhtxhphoaeydh/settings/database
2. Scroll to **Connection string**
3. Select **URI** tab and the **Transaction pooler** mode (port 6543)
4. Copy the value, replace `[YOUR-PASSWORD]` with the database password
5. If you do not have the password, click **Reset database password** in the same page

Format:
```
postgresql://postgres.mlltpfszhtxhphoaeydh:YOUR_PASSWORD@aws-0-us-east-1.pooler.supabase.com:6543/postgres
```

**Important:** All three services (`auth`, `game`, `importer`) use the **same** `DATABASE_URL`. They are isolated by Postgres schema (`profile`, `games`, `importer`).

### 4. Get BGG credentials (optional)

Only needed if you want to test BGG sync locally. The importer service runs without them but disables the sync feature.

#### Option A: Use the bundled helper

```sh
cd services/monolith
make bgg-login
```

This prompts for your BGG username and password (via `ADMIN_USERNAME` / `ADMIN_PASSWORD` env vars), logs in, and prints a `BGG_COOKIE=...` line you paste into `services/importer/.env`.

#### Option B: Manual cookie copy

1. Log in at https://boardgamegeek.com
2. Open DevTools → Application → Cookies → `boardgamegeek.com`
3. Copy the `bggusername` and `SessionID` cookie values
4. Combine: `BGG_COOKIE="bggusername=YOUR_USERNAME; SessionID=abc123..."`

### 5. Configure local `.env` files

Copy each `.env.example` and fill in the secrets from the previous steps.

```sh
cp services/gateway/.env.example  services/gateway/.env
cp services/auth/.env.example     services/auth/.env
cp services/game/.env.example     services/game/.env
cp services/importer/.env.example services/importer/.env
cp web/.env.example               web/.env

# Open all .env files to fill in secrets
$EDITOR services/gateway/.env services/auth/.env services/game/.env services/importer/.env web/.env
```

Then edit each:

**`services/gateway/.env`:**
```env
PORT=8000
SUPABASE_JWT_SECRET=<paste from step 3>
AUTH_SERVICE_URL=http://localhost:8001
GAME_SERVICE_URL=http://localhost:8002
IMPORTER_SERVICE_URL=http://localhost:8003
ALLOWED_ORIGIN=http://localhost:5173
```

**`services/auth/.env`:**
```env
PORT=8001
DATABASE_URL=<paste from step 3>
```

**`services/game/.env`:**
```env
PORT=8002
DATABASE_URL=<paste from step 3>
DATA_DIR=data/uploads
```

**`services/importer/.env`:**
```env
PORT=8003
DATABASE_URL=<paste from step 3>
GAME_SERVICE_URL=http://localhost:8002
BGG_TOKEN=                  # leave empty unless you have one
BGG_COOKIE=                 # paste from step 4 if testing sync
SYNC_LIMIT_USER=3
SYNC_LIMIT_ADMIN=20
```

**`web/.env`:**
```env
# Leave empty in dev — Vite proxies /api/* to gateway on :8000
VITE_API_BASE_URL=
```

**Run database migrations** (one-time, per-service):

```sh
# Auth schema
make -C services/auth migrate-up

# Game schema
make -C services/game migrate-up

# Importer schema
make -C services/importer migrate-up
```

These create the `profile`, `games`, and `importer` schemas in your Supabase database.

---

## Local Development

### Start everything

```sh
make dev-all
```

Spins up a tmux session named `mbgc` with one window per service:

| Window | Service | Port |
|---|---|---|
| `gateway` | `services/gateway` | `:8000` |
| `auth` | `services/auth` | `:8001` |
| `game` | `services/game` | `:8002` |
| `importer` | `services/importer` | `:8003` |
| `monolith` | `services/monolith` | `:8080` |
| `web` | Vite dev server | `:5173` |

**Attach to logs:**
```sh
tmux attach -t mbgc
# Inside tmux: ctrl+b then 1-7 to switch windows
# Detach: ctrl+b then d
```

**Stop everything:**
```sh
tmux kill-session -t mbgc
```

### Verify it's running

```sh
# All services healthy?
bash scripts/e2e-smoke.sh

# Manual checks
curl http://localhost:8000/healthz   # gateway → {"data":{"status":"ok"}}
curl http://localhost:8001/healthz   # auth    → {"status":"ok"}
curl http://localhost:8002/healthz   # game    → {"status":"ok"}
curl http://localhost:8003/healthz   # importer→ {"status":"ok"}
open http://localhost:5173           # web frontend
```

### Run a single service

```sh
cd services/gateway
make dev
```

Or run directly:
```sh
cd services/auth
go run ./cmd/server
```

### Tidy / build / test

```sh
make tidy           # go mod tidy in every Go module
make build          # build all service binaries
make test           # go test in every Go module
make test-v         # verbose + race detector
make lint           # go vet
make clean          # remove built binaries
```

---

## Testing

### Smoke test (end-to-end)

The minimum viable POC test — verifies all services are alive and the gateway auth-gates traffic correctly:

```sh
bash scripts/e2e-smoke.sh
```

Asserts:
- All `/healthz` endpoints respond
- Gateway returns `401` on `/api/v1/games/`, `/api/v1/profile/`, `/api/v1/import/` without a JWT
- Gateway rejects fake JWT tokens with `401`
- CORS headers are present
- Response envelope has the `data` key

### Unit tests

```sh
make test               # all modules
make test-v             # with race detector
make -C services/game test-v   # one module
```

### Web E2E (Playwright)

Requires backend running.

```sh
make dev-all                 # in one terminal
cd web && bun run test:e2e   # in another
```

### Coverage

```sh
cd pkg/shared
make cover             # generates coverage.html
open coverage.html
```

Current coverage:
- `pkg/shared/apierr` — 100%
- `pkg/shared/envelope` — 100%
- `pkg/shared/httpx` — 20%
- All services — 0% (TODO)

---

## Deployment

### Production targets

| Component | Provider | URL |
|---|---|---|
| All Go services | GCP Cloud Run (`us-central1`) | `*-mbgc-*.run.app` |
| API gateway custom domain | GCP + Cloudflare | https://api.lumedina.dev |
| Web frontend | Cloudflare Pages | https://lumedina.dev |
| Postgres | Supabase | (private) |

### How deploys work

CI/CD lives entirely in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | PR or push to `dev`/`staging`/`main` | Build + test all services + web lint + infra lint |
| `deploy.yml` | Push to `main` | Deploys only services that changed (path-filtered) |
| `deploy-cloud-run.yml` | Reusable | Builds Docker image, pushes to Artifact Registry, runs `gcloud run deploy` |

GCP authentication uses **Workload Identity Federation** — no service account keys committed.

### Branching

```
feature/*  →  dev  →  staging  →  main
```

PRs required for `dev → staging` and `staging → main`. Direct push to `main`/`staging` is blocked.

### Manually trigger a deploy

```sh
# Deploy from current branch
gh workflow run deploy.yml --ref staging

# Watch progress
gh run watch
```

### Cloud Run env vars (production)

Set via `gcloud run services update --set-env-vars` on each service. Terraform does not manage these — they live in the service's runtime config:

```sh
PROJECT=myboardgamecollection-494214
REGION=us-central1

# Gateway needs the JWT secret
gcloud run services update mbgc-gateway --region $REGION --project $PROJECT \
  --set-env-vars=SUPABASE_JWT_SECRET=...,ALLOWED_ORIGIN=https://lumedina.dev

# Auth, game, importer need the DB URL
for svc in mbgc-auth-service mbgc-game-service mbgc-importer-service; do
  gcloud run services update $svc --region $REGION --project $PROJECT \
    --set-env-vars=DATABASE_URL=...
done
```

---

## GitHub Secrets Setup

The CI/CD workflows need these secrets on the `LuisMedinaG/mbgc` repo. Run **one-time** to set them:

```sh
sh set-deploy-secrets.sh
```

Or set manually:

```sh
REPO=LuisMedinaG/mbgc

# GCP — fetched via gcloud
gh secret set GCP_PROJECT_ID --repo $REPO --body "myboardgamecollection-494214"

gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --repo $REPO --body \
  "$(gcloud iam workload-identity-pools providers describe github \
     --workload-identity-pool=github-actions --location=global \
     --project=myboardgamecollection-494214 --format='value(name)')"

gh secret set GCP_SERVICE_ACCOUNT --repo $REPO --body \
  "github-deploy@myboardgamecollection-494214.iam.gserviceaccount.com"

gh secret set GCP_RUNTIME_SERVICE_ACCOUNTS --repo $REPO --body \
  "$(gcloud iam service-accounts list --project=myboardgamecollection-494214 \
     --filter='email:run-' --format='value(email)' | tr '\n' ',' | sed 's/,$//')"

# Cloudflare — from infra/environments/prod/terraform.tfvars
gh secret set CLOUDFLARE_API_TOKEN --repo $REPO --body "<from terraform.tfvars>"
gh secret set CLOUDFLARE_ACCOUNT_ID --repo $REPO --body "b54fbd0d522b22fc747619b57608bb72"
```

**Verify (names only — values are write-only by design):**
```sh
gh secret list --repo LuisMedinaG/mbgc
```

You can also manage secrets at https://github.com/LuisMedinaG/mbgc/settings/secrets/actions

---

## Troubleshooting

### `make dev-all` — pane is dead

A service crashed on startup. Most common causes:

| Symptom | Fix |
|---|---|
| `ERROR required env var not set key=SUPABASE_JWT_SECRET` | Fill in `services/gateway/.env` |
| `ERROR required env var not set key=DATABASE_URL` | Fill in `services/auth/.env`, `services/game/.env`, `services/importer/.env` |
| `bind: address already in use` | Another process holds the port: `lsof -ti:8080 \| xargs kill -9` |
| `vite: command not found` | Run `cd web && bun install` |
| `failed to connect to database` | Check Supabase pooler URL and password |

Inspect a dead pane:
```sh
tmux capture-pane -t mbgc:gateway -p -S -50
```

### Importer pre-existing bug

`services/importer` has stub HTTP client to game-service — `Sync` and `CSVImport` return placeholder data. The healthz check works, but actual import is not implemented yet.

### Module not found / import path errors

```sh
go work sync
make tidy
```

If still broken, check that `go.work` lists every module:
```sh
cat go.work
```

### CI failing on `tflint` or `eslint`

Both are set to `continue-on-error: true` in `.github/workflows/ci.yml` — they will not block merging. Real failures show up under `Go Build & Test`.

---

## Project Layout

```
mbgc/
├── pkg/shared/                # Shared Go library
│   ├── apierr/                # Sentinel errors + machine codes
│   ├── envelope/              # JSON wire types
│   └── httpx/                 # HTTP middleware + write helpers
├── services/
│   ├── gateway/               # API gateway (JWT + reverse proxy)
│   ├── auth/                  # Profile service
│   ├── game/                  # Games + collections + player aids
│   ├── importer/              # BGG sync + CSV import
│   └── monolith/              # [DEPRECATED] Original SQLite app
├── web/                       # React + Vite + TypeScript + Tailwind
├── infra/                     # Terraform — GCP / Cloudflare / Supabase
│   ├── environments/prod/
│   └── modules/
├── scripts/
│   └── e2e-smoke.sh           # End-to-end smoke test
├── .github/workflows/         # CI/CD
│   ├── ci.yml
│   ├── deploy.yml
│   └── deploy-cloud-run.yml
├── go.work                    # Go workspace — all modules
├── Makefile                   # Root convenience commands
├── set-deploy-secrets.sh      # GitHub secrets bootstrap
├── AGENTS.md                  # AI agent operating rules
├── CLAUDE.md                  # Claude AI context
└── README.md                  # This file
```

Each service follows the same internal structure:

```
services/<name>/
├── cmd/server/main.go         # Entry point
├── internal/
│   ├── config/                # Env var loading
│   ├── handler/               # HTTP handlers
│   ├── service/               # Business logic
│   ├── store/                 # DB access
│   └── model/                 # Domain types
├── migrations/                # SQL migrations (psql-applied)
├── deploy/
│   ├── Dockerfile             # Multi-stage Go build
│   └── fly.toml               # [legacy] Fly.io config
├── .env.example
├── Makefile
└── go.mod
```

---

## Contributing

1. Branch from `dev`: `git checkout -b feature/your-feature dev`
2. Commit subject is imperative, max 50 chars: `add: ...`, `fix: ...`, `refactor: ...`
3. Run `make test` and `bash scripts/e2e-smoke.sh` before pushing
4. Open PR `feature/* → dev`, then `dev → staging`, then `staging → main`
5. Direct pushes to `main` and `staging` are blocked

See [AGENTS.md](./AGENTS.md) for repo-wide rules and [CLAUDE.md](./CLAUDE.md) for the AI context.

---

## License

Private — personal project.
