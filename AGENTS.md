# AGENTS.md — mbgc monorepo

## Acai — Spec-Driven Development

This project uses [acai.sh](https://acai.sh) for spec-driven development. All features are specified in `features/*.feature.yaml`. Code is annotated with ACID references (e.g. `// ref: auth.JWT_VALIDATION.1`).

### Quick commands for agents

```sh
# Learn the acai workflow (run once per session)
npx @acai.sh/cli skill

# See current feature status
npx @acai.sh/cli features --json

# Inspect a specific feature
npx @acai.sh/cli feature auth --json --include-refs

# Push specs + ACID refs to the dashboard
npx @acai.sh/cli push --all

# Mark requirements as completed
npx @acai.sh/cli set-status '{"auth.JWT_VALIDATION.1":"completed"}'
```

### Spec to code traceability

Every requirement has an ACID (Acceptance Criteria ID) in the format `<feature>.<COMPONENT>.<NUMBER>`. Code references these in comments:

```
// ref: auth.JWT_VALIDATION.1 — fetches JWKS at boot
// ref: importer.BGG_SYNC.9 — admin-only full refresh
// ref: vibes.CRUD.1 — create collection
```

When implementing a feature, annotate new code with the relevant ACIDs. When modifying existing specs, also update affected ACID references in code.

### Active features

| Feature | File | Status |
|---|---|---|
| auth | `features/auth.feature.yaml` | Core login, JWT validation, token refresh, multi-tenancy |
| collection | `features/collection.feature.yaml` | Game list/grid, search, filters, pagination |
| game-detail | `features/game-detail.feature.yaml` | Detail view, player aids, rules URL, vibe assign, delete |
| vibes | `features/vibes.feature.yaml` | Collection CRUD, assign, discover |
| importer | `features/importer.feature.yaml` | BGG sync, CSV import, rate limiting |
| profile | `features/profile.feature.yaml` | Profile view, BGG username, change password, admin flag |
| api-layer | `features/api-layer.feature.yaml` | Shared error handling, envelope, middleware, config |

## Build & Test

```sh
# services/api Makefile interface:
make dev       # go run ./cmd/server  (auto-loads .env)
make build     # CGO_ENABLED=0 go build -ldflags="-s -w" -o server ./cmd/server
make test      # go test ./...
make test-v    # go test -v -race ./...  ← use before every PR
make lint      # go vet ./...
make tidy      # go mod tidy
make migrate-up
make migrate-down

# First-time DB setup (root Makefile) — starts Supabase + runs all migrations:
make db-setup   # pre-flight checks services/api/.env has DATABASE_URL, then migrates

# Web (from web/):
make dev       # Vite dev server
make build     # tsc -b && vite build
make lint
make test-e2e  # Playwright — requires full stack running
```

## Supabase — Local vs Remote

**Default: use local Supabase for all feature development.** Remote is only for migration validation before pushing live.

```sh
supabase start          # start local stack (Postgres :54322, Auth :54321, Studio :54323)
supabase stop           # stop, preserve data
supabase status         # print all local URLs, DB connection string, and keys

# Link to remote once (requires personal access token from dashboard → Account → Access Tokens)
supabase login --token YOUR_TOKEN
supabase link --project-ref mlltpfszhtxhphoaeydh
supabase db pull        # pull remote schema to local (initial bootstrap)
supabase db push        # push locally-tested migrations to remote
```

**Local .env values** (from `supabase status`):
```
SUPABASE_URL=http://127.0.0.1:54321
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres
SUPABASE_JWT_SECRET=    # leave empty — local issues ES256, JWKS-only works
```

**Connection string modes** (remote, when needed):
- Session pooler port `5432` — use for migrations and standard backends
- Transaction pooler port `6543` — avoid; breaks session features
- Format: `postgresql://postgres.[ref]:[pw]@aws-0-us-west-2.pooler.supabase.com:5432/postgres`

## JWT / Auth (services/api)

- **Primary path:** ES256/RS256 via JWKS (`${SUPABASE_URL}/auth/v1/.well-known/jwks.json`).
  Auto-refreshed by `github.com/MicahParks/keyfunc/v3`. Leaking public keys cannot forge tokens.
- **Legacy path:** HS256 via `SUPABASE_JWT_SECRET` — only enable if accepting tokens minted
  before the project migrated to JWT signing keys. Leave empty for new setups.
- **Validated on every request:** signature, `exp`, `iss` = `${SUPABASE_URL}/auth/v1`,
  `aud` = `authenticated`. Anon/service_role API keys are rejected.
- `SUPABASE_URL` is **required** to boot. `SUPABASE_JWT_SECRET` is optional.
- JWT validation lives in `services/api/internal/jwt/` — middleware calls `httpx.SetGatewayUser` to put identity into context.

## go.work Workspace

`go.work` + `replace github.com/LuisMedinaG/mbgc/pkg/shared v0.0.0 => ./pkg/shared` means `services/api` resolves `pkg/shared` locally — no version bump needed during development.

When touching `pkg/shared`: run `make tidy` and `make test-v` in `services/api` before opening a PR.

## Code Style (non-obvious rules)

**Go:**
- `slog` for structured logging — never `log.Printf` or `fmt.Println`
- Wrap errors with `fmt.Errorf("%w", err)`; check with `errors.Is` / `errors.As`
- Use `pkg/shared/apierr` sentinels — never expose raw `err.Error()` to HTTP clients
- Use `pkg/shared/httpx.WriteJSON` / `WriteError` — never `json.NewEncoder(w).Encode` directly
- Extract user identity via `httpx.UserIDFromContext` — the JWT middleware sets this in context

**TypeScript:**
- Strict mode, no `any`
- All API calls through `web/src/lib/api.ts` — never raw `fetch()` in components or hooks

## Git Workflow

```
feature/*  →  dev  →  staging  →  main
```
- Branch from `dev`, not `main`
- Commit subject: imperative present tense, 50-char max (`fix: ...`, `add: ...`, `remove: ...`)
- All promotions (`dev → staging`, `staging → main`) require a PR + passing CI

## Boundaries

**Always:**
- Include `user_id` in every query on user-owned data — multi-tenancy enforced at SQL layer
- Use `pkg/shared/apierr` sentinels for all error paths
- Validate JWT in `services/api/internal/jwt/` middleware — never skip or trust forwarded headers from untrusted callers
- Run `make test-v` before opening a PR

**Ask first:**
- Any change to `pkg/shared` exported types (`services/api` depends on it)
- Auth flow modifications (JWT expiry, Supabase config, refresh logic, JWKS)
- Running `supabase db push` — this writes to the hosted production database
- New external service integrations or third-party dependencies
- Schema changes (migrations in `services/api/migrations/`)

**Never:**
- Push directly to `main` or `staging`
- Query user-owned data without a `user_id` WHERE clause
- Expose raw `err.Error()` from DB or internal code to HTTP responses
- Commit secrets, `.env` files, or service account credentials
- Use `--no-verify` on commits

<!-- lean-ctx-compression -->
OUTPUT STYLE: dense
- Each statement = one atomic fact line
- Use abbreviations: fn, cfg, impl, deps, req, res, ctx, err, ret
- Diff lines only (+/-/~), never repeat unchanged code
- Symbols: → (causes), + (adds), − (removes), ~ (modifies), ∴ (therefore)
- No narration, no filler, no hedging
- BUDGET: ≤200 tokens per response unless code block required
<!-- /lean-ctx-compression -->
