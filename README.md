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
                    │  gateway (JWT + CORS)   │   :8000  → api.your-domain.dev
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

The microservices need **two required values** from Supabase (plus one optional legacy value):

| Value | Used by | Required? |
|---|---|---|
| `SUPABASE_URL` | gateway | **Yes** — drives JWT verification |
| `DATABASE_URL` | auth, game, importer | **Yes** — Postgres connection |
| `SUPABASE_JWT_SECRET` | gateway | Optional — legacy HS256 fallback only |

**Project ref:** `your-project-ref` · **Dashboard:** https://supabase.com/dashboard/project/your-project-ref

#### Install + log in to the Supabase CLI (recommended, avoids guessing)

```sh
brew install supabase/tap/supabase
supabase login                       # opens browser, stores an access token

# List your projects — shows the ref and the API URL for each
supabase projects list
# REFERENCE ID            NAME                  REGION       API URL
# your-project-ref    MyBoardGameCollection us-west-2    https://your-project-ref.supabase.co
```

#### `SUPABASE_URL` (required)

This is the project's API URL: `https://<project-ref>.supabase.co`. The gateway
appends `/auth/v1/.well-known/jwks.json` to it and fetches Supabase's **public**
signing keys to verify every access token.

```sh
SUPABASE_URL=https://your-project-ref.supabase.co
```

**How verification works (ES256 / JWKS):** Supabase has migrated to **JWT
Signing Keys** — asymmetric **ES256** (ECDSA on the P-256 curve + SHA-256).
Supabase signs each token with a **private** key it never reveals; the gateway
verifies with the matching **public** key. Public keys are published, by `kid`
(key id), at the project's JWKS endpoint:

```sh
curl https://your-project-ref.supabase.co/auth/v1/.well-known/jwks.json
# { "keys": [ { "kid": "...", "kty": "EC", "crv": "P-256", "alg": "ES256", ... } ] }
```

The token's header carries the `kid`; the gateway matches it to a public key,
checks the signature, and also validates `exp`, `iss`
(`https://<ref>.supabase.co/auth/v1`), and `aud` (`authenticated`). Because the
gateway only ever holds *public* keys, leaking them cannot forge a token — this
is why ES256/JWKS is the secure, industry-standard setup. Key rotation (Dashboard
→ **Settings → JWT Keys → JWT Signing Keys**) is picked up automatically.

#### `SUPABASE_JWT_SECRET` (optional — legacy HS256 only)

Before signing keys, Supabase signed tokens with a single **HS256** shared
secret (symmetric — the same secret both *signs* and *verifies*, so anyone
holding it can mint tokens). After migrating, this is shown under Dashboard →
**Settings → JWT Keys → Legacy JWT Secret** and is **verify-only**.

Leave `SUPABASE_JWT_SECRET` **empty** for a clean JWKS-only setup. Set it only if
you still need to accept access tokens issued before the migration (they expire
within the access-token TTL, ~1 hour). To get it: Dashboard → **Settings → JWT
Keys → Legacy JWT Secret → Reveal**.

#### `DATABASE_URL` (required)

Get it from the Dashboard's **Connect** button (top bar) → **Connection string**
→ **URI**, under the **Session pooler** section. Replace `[YOUR-PASSWORD]` with
your database password (reset it on the same page if unknown).

Format (session pooler, port 5432):
```
postgresql://postgres.your-project-ref:YOUR_PASSWORD@aws-0-us-west-2.pooler.supabase.com:5432/postgres
```

Verify the connection with `psql` before wiring it into `.env`:
```sh
psql "postgresql://postgres.your-project-ref:YOUR_PASSWORD@aws-0-us-west-2.pooler.supabase.com:5432/postgres" -c '\conninfo'
```

For a hardened (verify-full) connection, download the SSL cert from the Connect
panel and pass it explicitly:
```sh
psql "sslmode=verify-full sslrootcert=/path/to/prod-supabase.cer \
  host=aws-0-us-west-2.pooler.supabase.com dbname=postgres \
  user=postgres.your-project-ref"
```

**Important:** All three services (`auth`, `game`, `importer`) use the **same**
`DATABASE_URL`. They are isolated by Postgres schema (`profile`, `games`,
`importer`).

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

Local Supabase (`supabase start` — recommended):
```env
PORT=8000
SUPABASE_URL=http://127.0.0.1:54321   # local auth, ES256 JWKS
SUPABASE_JWT_SECRET=                   # leave empty
AUTH_SERVICE_URL=http://localhost:8001
GAME_SERVICE_URL=http://localhost:8002
IMPORTER_SERVICE_URL=http://localhost:8003
ALLOWED_ORIGIN=http://localhost:5173
```

Remote Supabase (only when needed):
```env
PORT=8000
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_JWT_SECRET=                   # leave empty unless using legacy HS256
AUTH_SERVICE_URL=http://localhost:8001
GAME_SERVICE_URL=http://localhost:8002
IMPORTER_SERVICE_URL=http://localhost:8003
ALLOWED_ORIGIN=http://localhost:5173
```

**`services/auth/.env`:**
```env
PORT=8001
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres   # local
# DATABASE_URL=postgresql://postgres.[ref]:[pw]@aws-0-us-west-2.pooler.supabase.com:5432/postgres  # remote
```

**`services/game/.env`:**
```env
PORT=8002
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres   # local
DATA_DIR=data/uploads
```

**`services/importer/.env`:**
```env
PORT=8003
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres   # local
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

**Run database migrations** (one-time, automated):

Once each service `.env` has `DATABASE_URL` set (step 5 above), a single command handles everything:

```sh
make db-setup
```

This starts local Supabase and runs all three service migrations in order. Migrations are idempotent (`IF NOT EXISTS`) so re-running is safe. The pre-flight check will error with a clear message if any `.env` is missing or `DATABASE_URL` is unset.

To run per-service manually instead:

```sh
make -C services/auth migrate-up
make -C services/game migrate-up
make -C services/importer migrate-up
```

For the **remote** (linked) database, use the Supabase CLI — it handles auth and avoids connection string issues:

```sh
supabase db query --linked -f services/auth/migrations/001_init.up.sql
supabase db query --linked -f services/game/migrations/001_init.up.sql
supabase db query --linked -f services/importer/migrations/001_init.up.sql
```

These create the `profile`, `games`, and `importer` schemas in your Supabase database.

**Create an admin user** (after migrations):

1. Create the user in the Supabase Dashboard: Authentication → Users → Add User
2. Note the user's UUID, then promote them:

```sh
USER_ID="your-user-uuid-here"

# Set is_admin in profile.users
supabase db query --linked "INSERT INTO profile.users (id, is_admin) VALUES ('${USER_ID}', true) ON CONFLICT (id) DO UPDATE SET is_admin = true;"

# Set is_admin in Supabase Auth app_metadata (gateway reads this from the JWT)
supabase db query --linked "UPDATE auth.users SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || '{\"is_admin\": true}'::jsonb WHERE id = '${USER_ID}';"
```

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

### Supabase backend — local vs remote

There are two modes. Use **local for all feature development**; remote only when you need to validate against production data or push a migration live.

| | Local (`supabase start`) | Remote (hosted project) |
|---|---|---|
| **DB** | `127.0.0.1:54322` | Supabase pooler |
| **Auth / JWKS** | `http://127.0.0.1:54321` | `https://your-project-ref.supabase.co` |
| **Data isolation** | Fresh local copy | Production data |
| **Cost** | Free, offline-capable | Counts against project quotas |
| **Use for** | Feature dev, migration authoring | Migration validation, prod debugging |

#### Start / stop / inspect local stack

```sh
supabase start          # starts all containers (Postgres, Auth, Studio …)
supabase stop           # stops containers, preserves data
supabase stop --no-backup   # stops and discards data
supabase status         # prints all local URLs, keys, and DB connection string
```

`supabase status` is the canonical source for local credentials — no guessing:

```
DB URL  │ postgresql://postgres:postgres@127.0.0.1:54322/postgres
Auth    │ http://127.0.0.1:54321/auth/v1
Studio  │ http://127.0.0.1:54323
```

Use the values from `supabase status` to fill your `.env` files — see [Setup → step 5](#5-configure-local-env-files) for the full template.

#### Linking to remote (migration sync)

`supabase link` connects the CLI to the hosted project so you can pull the
remote schema and push tested migrations:

```sh
# One-time — requires supabase login with a personal access token
# Dashboard → Account → Access Tokens → Generate new token
supabase login --token YOUR_TOKEN
supabase link --project-ref your-project-ref

# Pull remote schema to seed local (first-time bootstrap)
supabase db pull

# After writing + testing a migration locally, push it to remote
supabase db push
```

Note: `supabase link` is only needed for migration management, not for running
the local dev stack itself.

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
| API gateway custom domain | GCP + Cloudflare | `https://api.your-domain.dev` |
| Web frontend | Cloudflare Pages | `https://your-domain.dev` |
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

### Infrastructure changes (Terraform)

Terraform manages Cloud Run service shells, Cloudflare DNS/Pages, Supabase auth settings, Artifact Registry, and Workload Identity Federation. It does **not** manage Cloud Run images, env vars, or resources — those are owned by service CI/CD.

**Prerequisites — set once per shell session:**
```sh
# Supabase Storage S3 credentials (not real AWS — Supabase uses an S3-compatible
# API for the mbgc-tfstate state bucket; Terraform's S3 backend requires SigV4)
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
2. Update `infra/environments/prod/terraform.tfvars`:
   ```
   supabase_access_token = "<new-token>"
   ```
3. Re-run `sh infra/scripts/bootstrap.sh` to push the updated token to GitHub secrets (keeps CI in sync)

**What Terraform manages vs what CI/CD manages:**

| Terraform (`infra/`) | Service CI/CD (`.github/workflows/`) |
|---|---|
| Cloud Run service shells (name, ingress, runtime SA, IAM) | Cloud Run image, env vars, scaling |
| `api.your-domain.dev` custom domain mapping | Traffic splitting |
| Cloudflare DNS + Pages project shell | Pages build settings, env vars |
| Supabase auth settings (JWT expiry, redirect URIs) | Database schema + migrations |
| Artifact Registry, WIF pool/provider, service accounts | — |

### Cloud Run env vars (production)

Set via `gcloud run services update --set-env-vars` on each service. Terraform does not manage these — they live in the service's runtime config:

```sh
PROJECT=your-gcp-project-id
REGION=us-central1

# Gateway needs the Supabase URL (drives JWKS verification)
gcloud run services update mbgc-gateway --region $REGION --project $PROJECT \
  --set-env-vars=SUPABASE_URL=https://your-project-ref.supabase.co,ALLOWED_ORIGIN=https://your-domain.dev
# SUPABASE_JWT_SECRET is optional — add it only for legacy HS256 fallback

# Auth, game, importer need the DB URL
for svc in mbgc-auth-service mbgc-game-service mbgc-importer-service; do
  gcloud run services update $svc --region $REGION --project $PROJECT \
    --set-env-vars=DATABASE_URL=...
done
```

---

## GitHub Secrets Setup

All secrets live on `LuisMedinaG/mbgc`. Run **once after `terraform apply`** — bootstrap handles everything:

```sh
sh infra/scripts/bootstrap.sh
```

Bootstrap writes local credential files and pushes all required secrets to this repo. Requires `jq`, `gh auth`, `gcloud` ADC, and the S3 env vars set (see [Infrastructure changes](#infrastructure-changes-terraform)).

**Secrets pushed by bootstrap:**

| Secret | Source | Used by |
|---|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `terraform output` | All Cloud Run deploy jobs |
| `GCP_SERVICE_ACCOUNT` | `terraform output` | All Cloud Run deploy jobs |
| `GCP_PROJECT_ID` | constant | All Cloud Run deploy jobs |
| `GCP_RUNTIME_SA_GATEWAY` | `terraform output` | `deploy-gateway` job |
| `GCP_RUNTIME_SA_AUTH` | `terraform output` | `deploy-auth` job |
| `GCP_RUNTIME_SA_GAME` | `terraform output` | `deploy-game` job |
| `GCP_RUNTIME_SA_IMPORTER` | `terraform output` | `deploy-importer` job |
| `GCP_RUNTIME_SA_MONOLITH` | `terraform output` | `deploy-monolith` job |
| `CLOUDFLARE_API_TOKEN` | prompted | `deploy-web` job |
| `CLOUDFLARE_ACCOUNT_ID` | prompted | `deploy-web` job |

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
| `ERROR required env var not set key=SUPABASE_URL` | Fill in `services/gateway/.env` |
| `init JWKS from ...` on gateway start | `SUPABASE_URL` wrong/unreachable — the gateway fetches public keys at boot |
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
├── infra/scripts/bootstrap.sh           # provisions GCP SA, writes local creds, pushes GitHub secrets
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
