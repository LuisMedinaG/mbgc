#!/usr/bin/env bash
# Writes CLAUDE.md (and AGENTS.md) context files for every mbgc-* repo
# plus the parent workspace folder.
#
# Run from anywhere on your Mac:
#   bash ~/Documents/Projects/mbgc/myboardgamecollection/scripts/setup-mbgc-claude-md.sh
#
# Safe to re-run — only creates files that do NOT already exist.

set -euo pipefail

ROOT="$HOME/Documents/Projects/mbgc"

write_if_missing() {
  local path="$1"
  local content="$2"
  if [ -f "$path" ]; then
    echo "  skip  $path (already exists)"
  else
    echo "$content" > "$path"
    echo "  wrote $path"
  fi
}

echo "==> mbgc context file setup"
echo "    root: $ROOT"
echo ""

# ---------------------------------------------------------------------------
# 1. PARENT WORKSPACE — mbgc/CLAUDE.md
# ---------------------------------------------------------------------------
write_if_missing "$ROOT/CLAUDE.md" \
'# mbgc — Ecosystem Context

Personal board game collection app. Originally a Go monolith (`myboardgamecollection`),
being decomposed into focused microservices. Both coexist during migration.

## Services

| Repo | Lang | Role | Deploy |
|---|---|---|---|
| `myboardgamecollection` | Go | Monolith (HTMX + REST API) — full feature set | Fly.io |
| `mbgc-gateway` | Go | API gateway — JWT validation, routing, CORS | Fly.io |
| `mbgc-auth-service` | Go | Profile service — BGG username, quotas, admin roles (Supabase auth) | Fly.io |
| `mbgc-game-service` | Go | Core domain — games, collections, player aids, file uploads | Fly.io |
| `mbgc-importer-service` | Go | BGG sync + CSV import | Fly.io |
| `mbgc-web` | TypeScript | React frontend | Cloudflare Pages |
| `mbgc-shared` | Go | Shared module — response envelope, error codes, HTTP middleware | (library) |
| `mbgc-infra` | HCL | Terraform IaC — Fly, Cloudflare, Supabase | — |

## Request Flow

```
Browser / mbgc-web
      │
      ▼
mbgc-gateway  (validates JWT, routes by path prefix)
      ├──▶ mbgc-auth-service     /auth/*  /profile/*
      ├──▶ mbgc-game-service     /games/* /collections/* /player-aids/*
      └──▶ mbgc-importer-service /import/*
```

The monolith (`myboardgamecollection`) runs independently and is not behind the gateway.

## Shared Conventions

- **Language:** Go 1.25 (services) · TypeScript / React (web)
- **Auth:** JWT — access tokens (15 min), refresh tokens (30 day)
- **Response envelope:** `{ "data": ... }` success · `{ "error": "..." }` failure
- **Pagination:** top-level `total`, `page`, `per_page` on list responses
- **Errors:** sentinel errors in `mbgc-shared` — never leak raw DB errors to clients
- **DB:** SQLite (`modernc.org/sqlite`) in monolith; services may use Postgres via Supabase

## Branching Strategy (all repos)

```
feature/*  →  dev  →  staging  →  main
```

Promotion: `dev → staging` and `staging → main` require PRs.
Direct push to `main`/`staging` is blocked (admin bypass exists for emergencies).

## Infrastructure

- **Fly.io** — all Go services (persistent volume at `/data` for monolith)
- **Cloudflare Pages** — `mbgc-web` frontend
- **Supabase** — auth provider for microservices
- **Terraform** — `mbgc-infra` is the single source of truth for all cloud resources
'

# ---------------------------------------------------------------------------
# 2. PARENT WORKSPACE — mbgc/AGENTS.md  (same content, different tool)
# ---------------------------------------------------------------------------
write_if_missing "$ROOT/AGENTS.md" \
'# mbgc — Ecosystem Context

Personal board game collection app. Originally a Go monolith (`myboardgamecollection`),
being decomposed into focused microservices. Both coexist during migration.

## Services

| Repo | Lang | Role | Deploy |
|---|---|---|---|
| `myboardgamecollection` | Go | Monolith (HTMX + REST API) — full feature set | Fly.io |
| `mbgc-gateway` | Go | API gateway — JWT validation, routing, CORS | Fly.io |
| `mbgc-auth-service` | Go | Profile service — BGG username, quotas, admin roles (Supabase auth) | Fly.io |
| `mbgc-game-service` | Go | Core domain — games, collections, player aids, file uploads | Fly.io |
| `mbgc-importer-service` | Go | BGG sync + CSV import | Fly.io |
| `mbgc-web` | TypeScript | React frontend | Cloudflare Pages |
| `mbgc-shared` | Go | Shared module — response envelope, error codes, HTTP middleware | (library) |
| `mbgc-infra` | HCL | Terraform IaC — Fly, Cloudflare, Supabase | — |

## Request Flow

```
Browser / mbgc-web
      │
      ▼
mbgc-gateway  (validates JWT, routes by path prefix)
      ├──▶ mbgc-auth-service     /auth/*  /profile/*
      ├──▶ mbgc-game-service     /games/* /collections/* /player-aids/*
      └──▶ mbgc-importer-service /import/*
```

The monolith (`myboardgamecollection`) runs independently and is not behind the gateway.

## Shared Conventions

- **Language:** Go 1.25 (services) · TypeScript / React (web)
- **Auth:** JWT — access tokens (15 min), refresh tokens (30 day)
- **Response envelope:** `{ "data": ... }` success · `{ "error": "..." }` failure
- **Pagination:** top-level `total`, `page`, `per_page` on list responses
- **Errors:** sentinel errors in `mbgc-shared` — never leak raw DB errors to clients
- **DB:** SQLite (`modernc.org/sqlite`) in monolith; services may use Postgres via Supabase

## Branching Strategy (all repos)

```
feature/*  →  dev  →  staging  →  main
```

Promotion: `dev → staging` and `staging → main` require PRs.
Direct push to `main`/`staging` is blocked (admin bypass exists for emergencies).

## Infrastructure

- **Fly.io** — all Go services (persistent volume at `/data` for monolith)
- **Cloudflare Pages** — `mbgc-web` frontend
- **Supabase** — auth provider for microservices
- **Terraform** — `mbgc-infra` is the single source of truth for all cloud resources
'

# ---------------------------------------------------------------------------
# 3. mbgc-shared
# ---------------------------------------------------------------------------
write_if_missing "$ROOT/mbgc-shared/CLAUDE.md" \
'# mbgc-shared

Shared Go module imported by all mbgc microservices. Contains the contract
that keeps services consistent — do not break exported types without updating
all consumers.

## Module path

```
github.com/LuisMedinaG/mbgc-shared
```

## What lives here

| Package | Contents |
|---|---|
| `envelope` | Response wrapper: `{ "data": ... }` / `{ "error": "..." }` + pagination helpers |
| `apierr` | Sentinel error codes (`ErrDuplicate`, `ErrNotFound`, `ErrUnauthorized`, …) |
| `middleware` | Reusable HTTP middleware: JWT validation, CORS, rate limiting, security headers |
| `model` | Shared domain structs (e.g. `UserClaims`) |

## Key rule

Never expose raw errors (DB, OS, network) to API consumers — map them to
sentinel errors here and handle them consistently in each service.

## Response envelope

```go
// Success
{ "data": <payload> }

// List (paginated)
{ "data": [...], "total": 42, "page": 1, "per_page": 20 }

// Error
{ "error": "not found" }
```

## Updating this module

1. Bump the version tag (`vX.Y.Z`) after any breaking change.
2. Update `go.mod` in every consuming service.
3. Keep backwards-compatible additions in minor versions.
'

# ---------------------------------------------------------------------------
# 4. mbgc-gateway
# ---------------------------------------------------------------------------
write_if_missing "$ROOT/mbgc-gateway/CLAUDE.md" \
'# mbgc-gateway

API gateway — the single ingress point for all mbgc microservice traffic.
Validates JWTs so downstream services can trust the forwarded identity.

## Stack

- **Language:** Go 1.25
- **Auth:** `github.com/golang-jwt/jwt/v5` — validates `Authorization: Bearer` tokens
- **Shared:** `github.com/LuisMedinaG/mbgc-shared` (middleware, envelope)

## Routing table

| Prefix | Upstream service |
|---|---|
| `/auth/*` | mbgc-auth-service |
| `/profile/*` | mbgc-auth-service |
| `/games/*` | mbgc-game-service |
| `/collections/*` | mbgc-game-service |
| `/player-aids/*` | mbgc-game-service |
| `/import/*` | mbgc-importer-service |

## Responsibilities

- Validate JWT on every request; return `401` if invalid/missing
- Forward `X-User-ID` header to upstream services (extracted from JWT claims)
- CORS — allow `mbgc-web` origin
- Rate limiting at the edge

## What the gateway does NOT do

- Business logic
- Database access
- Token issuance (that is mbgc-auth-service)

## Commands

```sh
make dev    # go run .
make build  # outputs ./gateway binary
make test
```

## Deployment

Fly.io — `fly.toml` at repo root.
JWT secret injected via `JWT_SECRET` env var (set in Fly secrets).
'

# ---------------------------------------------------------------------------
# 5. mbgc-auth-service
# ---------------------------------------------------------------------------
write_if_missing "$ROOT/mbgc-auth-service/CLAUDE.md" \
'# mbgc-auth-service

Profile and authentication service. Delegates identity to Supabase and owns
mbgc-specific profile data: BGG username, sync quotas, admin flags.

## Stack

- **Language:** Go 1.25
- **Auth provider:** Supabase (JWT issued by Supabase, validated here and at gateway)
- **Shared:** `github.com/LuisMedinaG/mbgc-shared`

## Domain

- User profile (BGG username, display name, avatar)
- Sync quota — how many BGG imports a user can trigger per day
- Admin role — gates Full Refresh imports and other privileged ops
- Token refresh — issues mbgc access tokens (15 min) backed by Supabase session

## API surface (mounted under `/auth/*` and `/profile/*` at the gateway)

| Method | Path | Description |
|---|---|---|
| `POST` | `/auth/login` | Exchange Supabase credentials for mbgc JWT |
| `POST` | `/auth/refresh` | Refresh access token |
| `GET` | `/profile/me` | Current user profile |
| `PATCH` | `/profile/me` | Update BGG username etc. |

## Key env vars

| Var | Purpose |
|---|---|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Public anon key |
| `JWT_SECRET` | Signing secret (shared with gateway) |

## Commands

```sh
make dev
make test
```

## Deployment

Fly.io — `fly.toml` at repo root.
'

# ---------------------------------------------------------------------------
# 6. mbgc-game-service
# ---------------------------------------------------------------------------
write_if_missing "$ROOT/mbgc-game-service/CLAUDE.md" \
'# mbgc-game-service

Core domain service — owns everything about games, collections, and files.
Extracted from the monolith (`myboardgamecollection`); mirrors its data model.

## Stack

- **Language:** Go 1.25
- **DB:** SQLite (`modernc.org/sqlite`, pure Go) — file at `/data/games.db`
- **Shared:** `github.com/LuisMedinaG/mbgc-shared`

## Game Model — Key Fields

| Field | Type | DB column | Source |
|---|---|---|---|
| `Weight` | `float64` | `weight` | BGG `averageweight` |
| `Rating` | `float64` | `rating` | BGG `average` |
| `LanguageDependence` | `int` | `language_dependence` | BGG poll winner (0=unknown, 1–5) |
| `RecommendedPlayers` | `string` | `recommended_players` | BGG poll — comma-separated counts |

## Filters

All filters flow through `internal/filter/filter.go`:

| Param | Values |
|---|---|
| `players` | `1`, `2`, `2only`, `3`, `4`, `5plus` |
| `playtime` | `short`, `medium`, `long` |
| `weight` | `light`, `medium`, `heavy` |
| `rating` | `good` (≥6), `great` (≥7), `excellent` (≥8) |
| `lang` | `free` (1), `low` (2), `moderate` (3), `high` (≥4) |
| `rec_players` | `1`–`5` |

## DB Migration Pattern

New columns → `ALTER TABLE games ADD COLUMN … DEFAULT …` in `createTables()`.
Idempotent — SQLite silently ignores duplicate `ADD COLUMN`.

## API surface (mounted under `/games/*` etc. at the gateway)

Standard CRUD for games, collections, player aids, and file uploads.
All list endpoints support the filter params above.

## Commands

```sh
make dev
make test
make cover
```

## Deployment

Fly.io with persistent volume at `/data`.
'

# ---------------------------------------------------------------------------
# 7. mbgc-importer-service
# ---------------------------------------------------------------------------
write_if_missing "$ROOT/mbgc-importer-service/CLAUDE.md" \
'# mbgc-importer-service

Handles all external data ingestion: BGG collection sync and CSV import.
Extracted from the monolith; shares the same BGG client approach.

## Stack

- **Language:** Go 1.25
- **BGG client:** Custom XML fetch (`fetchThingsParsed`) + gobgg `GetCollection`
  - Custom fetch needed because gobgg`s `ThingResult` does not expose raw poll data
  - Both share the same authenticated, throttled `http.Client`
- **Shared:** `github.com/LuisMedinaG/mbgc-shared`

## Sync modes

| Mode | Trigger | Scope |
|---|---|---|
| **Incremental** | Normal sync | Newly added games only |
| **Full Refresh** | Admin-only — checkbox in UI or `{"full_refresh": true}` | Backfills `weight`, `rating`, `language_dependence`, `recommended_players` |

Full Refresh is required to populate stat fields on existing games.

## BGG rate limiting

All BGG requests go through the shared throttled client — do not add a
second client or you will hit BGG`s rate limit.

## API surface (mounted under `/import/*` at the gateway)

| Method | Path | Description |
|---|---|---|
| `POST` | `/import` | Trigger BGG sync (`full_refresh` flag for admins) |
| `POST` | `/import/csv` | Upload and import a CSV file |

## Key env vars

| Var | Purpose |
|---|---|
| `BGG_USERNAME` | BGG account for collection fetch |
| `BGG_PASSWORD` | BGG account password |
| `GAME_SERVICE_URL` | Internal URL of mbgc-game-service |

## Commands

```sh
make dev
make bgg-login   # grab BGG auth headers for testing
make test
```
'

# ---------------------------------------------------------------------------
# 8. mbgc-web
# ---------------------------------------------------------------------------
write_if_missing "$ROOT/mbgc-web/CLAUDE.md" \
'# mbgc-web

React frontend for mbgc — replaces the Go/HTMX templates from the monolith.
Deployed to Cloudflare Pages; talks exclusively to mbgc-gateway.

## Stack

- **Language:** TypeScript
- **Framework:** React
- **Deploy:** Cloudflare Pages
- **API:** mbgc-gateway (JWT in `Authorization: Bearer`)

## Auth flow

1. User logs in → mbgc-auth-service returns access + refresh tokens
2. Access token (15 min) stored in memory; refresh token in `httpOnly` cookie
3. On 401 → auto-refresh via `/auth/refresh`; on refresh failure → logout

## Commands

```sh
npm install
npm run dev      # local dev server
npm run build    # production build → dist/
npm run lint
npm run test
```

## Environment variables

| Var | Purpose |
|---|---|
| `VITE_API_BASE_URL` | mbgc-gateway base URL |

## Deployment

Push to `main` triggers Cloudflare Pages deploy automatically.
Preview deploys on every PR (Cloudflare integration).

## Key conventions

- No JS framework beyond React — keep it lean
- All API calls go through a central `api/` module that attaches the JWT header
- TypeScript strict mode — no `any`
'

# ---------------------------------------------------------------------------
# 9. mbgc-infra
# ---------------------------------------------------------------------------
write_if_missing "$ROOT/mbgc-infra/CLAUDE.md" \
'# mbgc-infra

Terraform source of truth for all mbgc cloud infrastructure.
One change here = one PR = one audit trail.

## Stack

- **IaC:** Terraform (HCL)
- **Providers:** Fly.io · Cloudflare · Supabase

## Layout

```
fly/          # Fly.io apps — one per Go service
cloudflare/   # DNS, Pages project, WAF rules
supabase/     # Auth project, DB config
```

## Managed resources

| Provider | Resources |
|---|---|
| Fly.io | Apps, volumes, secrets (via `fly secrets`) |
| Cloudflare | DNS records, Pages project, custom domain |
| Supabase | Auth project, JWT secret rotation |

## Workflow

```sh
terraform init
terraform plan   # always review before apply
terraform apply
```

Never run `terraform apply` without a preceding `plan` review.

## Secrets

Fly secrets (`JWT_SECRET`, `BGG_PASSWORD`, etc.) are set via `fly secrets set`
and are NOT stored in this repo or in Terraform state.
Only non-sensitive config lives in `.tf` files.

## State

Remote state — Terraform Cloud (or S3 backend, see `backend.tf`).
Never commit `.tfstate` files.
'

# ---------------------------------------------------------------------------
# 10. PARENT WORKSPACE — go.work (Go module workspace)
# ---------------------------------------------------------------------------
write_if_missing "$ROOT/go.work" \
'go 1.25

use (
	./mbgc-shared
	./mbgc-gateway
	./mbgc-auth-service
	./mbgc-game-service
	./mbgc-importer-service
)
'

# ---------------------------------------------------------------------------
# 11. PARENT WORKSPACE — Makefile (multi-repo commands)
# ---------------------------------------------------------------------------
write_if_missing "$ROOT/Makefile" \
'.PHONY: test-all test dev-all dev build-all build clean-all lint

test-all:
	@echo "==> running tests in all Go services"
	@for dir in mbgc-shared mbgc-gateway mbgc-auth-service mbgc-game-service mbgc-importer-service; do \
		echo "\n→ $$dir"; \
		make -C $$dir test || exit 1; \
	done
	@echo "\n✓ all tests passed"

test:
	@echo "==> running tests in all Go services"
	@cd "$${PWD}" && make test-all

dev-all:
	@echo "==> starting all services (tmux required)"
	@echo "    to stop: tmux kill-session -t mbgc"
	@tmux new-session -d -s mbgc
	@tmux new-window -t mbgc -n gateway "cd mbgc-gateway && make dev"
	@tmux new-window -t mbgc -n auth "cd mbgc-auth-service && make dev"
	@tmux new-window -t mbgc -n game "cd mbgc-game-service && make dev"
	@tmux new-window -t mbgc -n importer "cd mbgc-importer-service && make dev"
	@tmux new-window -t mbgc -n web "cd mbgc-web && npm run dev"
	@tmux list-windows -t mbgc

dev:
	@echo "==> starting all services"
	@make dev-all

build-all:
	@echo "==> building all Go services"
	@for dir in mbgc-gateway mbgc-auth-service mbgc-game-service mbgc-importer-service; do \
		echo "\n→ $$dir"; \
		make -C $$dir build || exit 1; \
	done

build: build-all

clean-all:
	@echo "==> cleaning all services"
	@for dir in mbgc-shared mbgc-gateway mbgc-auth-service mbgc-game-service mbgc-importer-service; do \
		echo "\n→ $$dir"; \
		make -C $$dir clean || true; \
	done

lint:
	@echo "==> linting all Go services"
	@for dir in mbgc-shared mbgc-gateway mbgc-auth-service mbgc-game-service mbgc-importer-service; do \
		echo "\n→ $$dir"; \
		cd $$dir && golangci-lint run ./... && cd ..; \
	done
'

echo ""
echo "Done. Files written to $ROOT."
echo ""
echo "Set up:"
echo "  • go.work — Go 1.25 workspace for local multi-module development"
echo "  • Makefile — multi-repo commands (make test-all, make dev-all, etc.)"
echo "  • CLAUDE.md + AGENTS.md — ecosystem context for AI tools"
echo "  • Service CLAUDE.md — per-repo context"
echo ""
echo "Next steps:"
echo "  1. cd $ROOT && go work use ./mbgc-shared ./mbgc-gateway ... (already done via go.work)"
echo "  2. Run: bash scripts/commit-and-push-claude-md.sh"
echo "  3. Open any service in Claude Code — parent CLAUDE.md loads automatically"
