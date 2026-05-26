# mbgc — My Board Game Collection

A personal board game collection app with BoardGameGeek (BGG) integration. Track games, organize collections, sync from BGG, and more.

**Live:** deploy your own — see [Deployment](#deployment)

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
  - [5. Configure local `.env`](#5-configure-local-env)
- [Local Development](#local-development)
- [Testing](#testing)
- [Deployment](#deployment)
- [GitHub Secrets Setup](#github-secrets-setup)
- [Troubleshooting](#troubleshooting)
- [Project Layout](#project-layout)
- [Contributing](#contributing)

---

## Architecture

Single Go API service behind Cloudflare Pages frontend.

```
                    ┌─────────────────────────┐
                    │   web (React + Vite)    │   :5173 dev / Cloudflare Pages prod
                    └───────────┬─────────────┘
                                │
                                ▼
                    ┌─────────────────────────┐
                    │  services/api           │   :8080  → api.lumedina.dev
                    │  (JWT + CORS + all      │
                    │   business logic)       │
                    └───────────┬─────────────┘
                                │
                          Supabase Postgres
                    (profile, games, importer schemas)
```

| Component | Path | Responsibility |
|---|---|---|
| `web` | React SPA | UI, talks only to `services/api` |
| `services/api` | Go | JWT validation, profile, games, collections, BGG import |
| `pkg/shared` | Go library | Response envelope, errors, HTTP middleware |
| `infra` | Terraform | GCP Cloud Run + Cloudflare + Supabase |

**Auth flow:** Supabase issues JWTs → `services/api` validates on every request via JWKS → extracts user identity into request context.

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

# Copy env template and fill in secrets (see Setup → step 5)
cp services/api/.env.example services/api/.env
cp web/.env.example          web/.env

# Open .env files to fill in secrets
$EDITOR services/api/.env web/.env

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
brew install go tmux gh terraform libpq
brew install --cask google-cloud-sdk docker
brew link --force libpq

# Install bun
curl -fsSL https://bun.sh/install | bash

# Authenticate
gh auth login
gcloud auth application-default login
```

### 3. Get Supabase credentials

`services/api` needs two required values from Supabase (plus one optional legacy value):

| Value | Required? | Purpose |
|---|---|---|
| `SUPABASE_URL` | **Yes** | JWKS endpoint for JWT verification |
| `DATABASE_URL` | **Yes** | Postgres connection |
| `SUPABASE_JWT_SECRET` | Optional | Legacy HS256 fallback only |

**Project ref:** `mlltpfszhtxhphoaeydh` · **Dashboard:** https://supabase.com/dashboard/project/mlltpfszhtxhphoaeydh

#### Install + log in to the Supabase CLI

```sh
brew install supabase/tap/supabase
supabase login                       # opens browser, stores an access token
supabase projects list               # shows ref and API URL for each project
```

#### `SUPABASE_URL` (required)

This is the project's API URL: `https://<project-ref>.supabase.co`. The API service
appends `/auth/v1/.well-known/jwks.json` to fetch Supabase's public signing keys.

**How verification works (ES256 / JWKS):** Supabase signs tokens with a private ES256
key; the API verifies with the matching public key from JWKS. Also validates `exp`,
`iss` (`https://<ref>.supabase.co/auth/v1`), and `aud` (`authenticated`). Key
rotation is picked up automatically.

#### `SUPABASE_JWT_SECRET` (optional — legacy HS256 only)

Leave empty for a clean JWKS-only setup. Set it only if you still need to accept
access tokens issued before the project migrated to asymmetric signing keys.

#### `DATABASE_URL` (required)

Get from Dashboard → **Connect** → **Connection string** → **URI** → Session pooler (port 5432).

```
postgresql://postgres.your-project-ref:YOUR_PASSWORD@aws-0-us-west-2.pooler.supabase.com:5432/postgres
```

Verify:
```sh
psql "postgresql://postgres.your-project-ref:YOUR_PASSWORD@aws-0-us-west-2.pooler.supabase.com:5432/postgres" -c '\conninfo'
```

### 4. Get BGG credentials (optional)

Only needed to test BGG sync locally. The importer runs without them but disables the sync feature.

1. Log in at https://boardgamegeek.com
2. Open DevTools → Application → Cookies → `boardgamegeek.com`
3. Copy `bggusername` and `SessionID` cookie values
4. Set `BGG_COOKIE="bggusername=YOUR_USERNAME; SessionID=abc123..."` in `services/api/.env`

### 5. Configure local `.env`

```sh
cp services/api/.env.example services/api/.env
cp web/.env.example web/.env
$EDITOR services/api/.env web/.env
```

**`services/api/.env`** (local Supabase — recommended):
```env
PORT=8080
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_JWT_SECRET=
ALLOWED_ORIGIN=http://localhost:5173
BGG_TOKEN=
BGG_COOKIE=
SYNC_LIMIT_USER=3
SYNC_LIMIT_ADMIN=20
```

**`web/.env`:**
```env
# Leave empty in dev — Vite proxies /api/* to services/api on :8080
VITE_API_BASE_URL=
```

**Run database migrations** (one-time):

```sh
make db-setup
```

Starts local Supabase and runs all migrations. Idempotent — safe to re-run. Pre-flight check errors with a clear message if `.env` is missing or `DATABASE_URL` is unset.

To run manually:
```sh
make -C services/api migrate-up
```

For the **remote** database:
```sh
supabase db query --linked -f services/api/migrations/001_profile.up.sql
supabase db query --linked -f services/api/migrations/002_games.up.sql
supabase db query --linked -f services/api/migrations/003_importer.up.sql
```

**Create an admin user** (after migrations):

1. Create the user in Supabase Dashboard: Authentication → Users → Add User
2. Promote them:

```sh
USER_ID="your-user-uuid-here"

supabase db query --linked "INSERT INTO profile.users (id, is_admin) VALUES ('${USER_ID}', true) ON CONFLICT (id) DO UPDATE SET is_admin = true;"
supabase db query --linked "UPDATE auth.users SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || '{\"is_admin\": true}'::jsonb WHERE id = '${USER_ID}';"
```

---

## Local Development

### Start everything

```sh
make dev-all
```

Spins up a tmux session named `mbgc` with two windows:

| Window | Service | Port |
|---|---|---|
| `api` | `services/api` | `:8080` |
| `web` | Vite dev server | `:5173` |

**Attach to logs:**
```sh
tmux attach -t mbgc
# Inside tmux: ctrl+b then 1-2 to switch windows
# Detach: ctrl+b then d
```

**Stop everything:**
```sh
tmux kill-session -t mbgc
```

### Verify it's running

```sh
bash scripts/e2e-smoke.sh

# Manual checks
curl http://localhost:8080/healthz   # → {"status":"ok"}
open http://localhost:5173           # web frontend
```

### Run the API service only

```sh
cd services/api
make dev
```

### Tidy / build / test

```sh
make -C services/api tidy
make -C services/api build
make -C services/api test
make -C services/api test-v    # verbose + race detector
make -C services/api lint
```

### Supabase backend — local vs remote

| | Local (`supabase start`) | Remote (hosted project) |
|---|---|---|
| **DB** | `127.0.0.1:54322` | Supabase pooler |
| **Auth / JWKS** | `http://127.0.0.1:54321` | `https://your-project-ref.supabase.co` |
| **Data isolation** | Fresh local copy | Production data |
| **Use for** | Feature dev, migration authoring | Migration validation, prod debugging |

```sh
supabase start          # starts all containers (Postgres, Auth, Studio …)
supabase stop           # stops containers, preserves data
supabase status         # prints all local URLs, keys, and DB connection string
```

---

## Testing

### Smoke test

```sh
bash scripts/e2e-smoke.sh
```

Asserts:
- `/healthz` responds with `ok`
- Unauthenticated requests to `/api/v1/*` return `401`
- Fake JWT tokens are rejected with `401`
- CORS headers are present

Override the API base URL: `API=http://localhost:8080 bash scripts/e2e-smoke.sh`

### Unit tests

```sh
make -C services/api test-v
make -C pkg/shared test
```

### Web E2E (Playwright)

Requires backend running.

```sh
make dev-all                 # in one terminal
cd web && bun run test:e2e   # in another
```

### Coverage

```sh
cd pkg/shared && go test ./... -coverprofile=coverage.out && go tool cover -html=coverage.out
```

Current coverage:
- `pkg/shared/apierr` — 100%
- `pkg/shared/envelope` — 100%
- `pkg/shared/httpx` — ~20%
- `services/api` — 0% (TODO)

---

## Deployment

### Production targets

| Component | Provider | URL |
|---|---|---|
| `services/api` | GCP Cloud Run (`us-central1`) | `mbgc-api-*.run.app` |
| API custom domain | GCP + Cloudflare | `https://api.lumedina.dev` |
| Web frontend | Cloudflare Pages | `https://lumedina.dev` |
| Postgres | Supabase | (private) |

### How deploys work

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | PR or push to `dev`/`staging`/`main` | Build + test `pkg/shared` + `services/api` + web lint + infra lint |
| `deploy.yml` | Push to `main` | Deploys `services/api` if changed, web if changed (path-filtered) |
| `deploy-cloud-run.yml` | Reusable | Builds Docker image, pushes to Artifact Registry, runs `gcloud run deploy` |

The `services/api` Docker build context is the repo root (so it can include `pkg/shared`). See `services/api/deploy/Dockerfile`.

GCP authentication uses **Workload Identity Federation** — no service account keys committed.

### Branching

```
feature/*  →  dev  →  staging  →  main
```

PRs required for `dev → staging` and `staging → main`. Direct push to `main`/`staging` is blocked.

### Manually trigger a deploy

```sh
gh workflow run deploy.yml --ref staging
gh run watch
```

### Infrastructure changes (Terraform)

Terraform manages the Cloud Run service shell, Cloudflare DNS/Pages, Supabase auth settings, Artifact Registry, and Workload Identity Federation. It does **not** manage Cloud Run images, env vars, or resources — those are owned by service CI/CD.

**Prerequisites — set once per shell session:**
```sh
# Supabase Storage S3 credentials (Terraform's S3 backend for the mbgc-tfstate bucket)
export AWS_ACCESS_KEY_ID=<supabase-s3-key>
export AWS_SECRET_ACCESS_KEY=<supabase-s3-secret>
# Get from: Supabase Dashboard → Storage → S3 Connection
```

**Apply a change:**
```sh
cd infra/environments/prod
terraform plan    # always review before applying
terraform apply
sh ../scripts/smoke.sh   # verify after apply
```

**Token rotation** (`supabase_access_token` expires or gets revoked):

Symptom: `terraform plan` errors with `401: {"message":"Unauthorized"}` on `supabase_settings.prod`.

Fix:
1. Generate a new token: `app.supabase.com → Account → Access Tokens`
2. Update `infra/environments/prod/terraform.tfvars`: `supabase_access_token = "<new-token>"`
3. Re-run `sh infra/scripts/bootstrap.sh` to push updated token to GitHub secrets

### Cloud Run env vars (production)

Set via `gcloud run services update`. Terraform does not manage these:

```sh
PROJECT=myboardgamecollection-494214
REGION=us-central1

gcloud run services update mbgc-api --region $REGION --project $PROJECT \
  --set-env-vars=SUPABASE_URL=https://mlltpfszhtxhphoaeydh.supabase.co,\
DATABASE_URL=<connection-string>,\
ALLOWED_ORIGIN=https://lumedina.dev,\
SYNC_LIMIT_USER=3,\
SYNC_LIMIT_ADMIN=20
```

---

## GitHub Secrets Setup

All secrets live on `LuisMedinaG/mbgc`. Run **once after `terraform apply`**:

```sh
sh infra/scripts/bootstrap.sh
```

**Secrets pushed by bootstrap:**

| Secret | Source | Used by |
|---|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `terraform output` | `deploy-api` job |
| `GCP_SERVICE_ACCOUNT` | `terraform output` | `deploy-api` job |
| `GCP_PROJECT_ID` | constant | `deploy-api` job |
| `GCP_RUNTIME_SA_API` | `terraform output` | `deploy-api` job |
| `CLOUDFLARE_API_TOKEN` | prompted | `deploy-web` job |
| `CLOUDFLARE_ACCOUNT_ID` | prompted | `deploy-web` job |

**Verify:**
```sh
gh secret list --repo LuisMedinaG/mbgc
```

---

## Troubleshooting

### `make dev-all` — pane is dead

| Symptom | Fix |
|---|---|
| `required env var not set key=SUPABASE_URL` | Fill in `services/api/.env` |
| `init JWKS from ...` error on startup | `SUPABASE_URL` wrong/unreachable — API fetches public keys at boot |
| `required env var not set key=DATABASE_URL` | Fill in `services/api/.env` |
| `bind: address already in use` | `lsof -ti:8080 \| xargs kill -9` |
| `vite: command not found` | Run `cd web && bun install` |
| `failed to connect to database` | Check Supabase pooler URL and password |

### Module not found / import path errors

```sh
go work sync
make -C services/api tidy
```

Check `go.work` lists both modules:
```sh
cat go.work
```

### CI failing on `tflint` or `eslint`

Both are set to `continue-on-error: true` — they will not block merging. Real failures show up under `Go Build & Test`.

---

## Project Layout

```
mbgc/
├── pkg/shared/                # Shared Go library
│   ├── apierr/                # Sentinel errors + machine codes
│   ├── envelope/              # JSON wire types
│   └── httpx/                 # HTTP middleware + write helpers
├── services/
│   └── api/                   # Single Go API service
│       ├── cmd/server/        # Entry point
│       ├── internal/
│       │   ├── config/        # Env var loading
│       │   ├── jwt/           # JWT verification middleware
│       │   ├── profile/       # Profile handler/service/store
│       │   ├── game/          # Games + collections handler/service/store
│       │   └── importer/      # BGG sync + CSV import
│       ├── migrations/        # SQL migrations (001_profile, 002_games, 003_importer)
│       ├── deploy/
│       │   └── Dockerfile     # Multi-stage build (build context = repo root)
│       ├── .env.example
│       ├── Makefile
│       └── go.mod
├── web/                       # React + Vite + TypeScript + Tailwind
├── infra/                     # Terraform — GCP / Cloudflare / Supabase
│   ├── environments/prod/
│   ├── modules/
│   └── scripts/bootstrap.sh   # Provisions GCP SA, writes local creds, pushes GitHub secrets
├── scripts/
│   └── e2e-smoke.sh           # End-to-end smoke test
├── .github/workflows/         # CI/CD
│   ├── ci.yml
│   ├── deploy.yml
│   └── deploy-cloud-run.yml
├── go.work                    # Go workspace
├── Makefile                   # Root convenience commands
├── AGENTS.md                  # AI agent operating rules
└── CLAUDE.md                  # Claude AI context
```

---

## Contributing

1. Branch from `dev`: `git checkout -b feature/your-feature dev`
2. Commit subject is imperative, max 50 chars: `add: ...`, `fix: ...`, `refactor: ...`
3. Run `make -C services/api test-v` and `bash scripts/e2e-smoke.sh` before pushing
4. Open PR `feature/* → dev`, then `dev → staging`, then `staging → main`
5. Direct pushes to `main` and `staging` are blocked

See [AGENTS.md](./AGENTS.md) for repo-wide rules and [CLAUDE.md](./CLAUDE.md) for AI context.

---

## License

Private — personal project.
