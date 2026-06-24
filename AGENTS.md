# AGENTS.md — mbgc monorepo

## Agent hooks

When given a task, agents MUST:
- **Before debugging errors**: search the runbook for known fixes — `rg "<error text>" docs/runbook/`. If no match, document the fix after resolving by loading the `add-runbook` skill.

## Setup & Build

> Full first-time setup guide: **[SETUP.md](./SETUP.md)**
> iOS-specific build/test: **[ios/AGENTS.md](./ios/AGENTS.md)**

```sh
# Root Makefile — primary entry points:
make setup-local   # first-time local setup (copies .env, starts Supabase, migrates)
make dev           # start API + web in tmux
make db-migrate    # apply pending migrations
make db-reset      # wipe + replay local DB
make build         # build API + web
make test          # run Go tests (pkg/shared + services/api with -race)
make lint          # lint Go + web + infra

# services/api Makefile:
make dev           # go run ./cmd/server  (auto-loads .env, runs migrations at startup)
make test-v        # go test -v -race ./...  ← use before every PR
make tidy          # go mod tidy

# Web (from web/):
make dev           # Vite dev server
make build         # tsc -b && vite build
make lint
make test-e2e      # Playwright — mocked, no backend needed; spins up its own isolated Vite server

# iOS (from ios/ — see ios/AGENTS.md for full details):
# Primary: xcode-gen MCP tasks `build_sim` / `test_sim`
# Fallback: xcodebuild -scheme MBGC -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

### Admin user

Set in `services/api/.env` — created automatically on first API boot:

```sh
SEED_ADMIN_EMAIL=you@example.com
SEED_ADMIN_PASSWORD=yourpassword
SUPABASE_SERVICE_ROLE_KEY=<from supabase status>
```

Idempotent — safe to leave set permanently.

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
- **Rate limiting:** Auth endpoints (login/refresh/logout) are rate-limited at 5 req/s per IP via `httpx.RateLimiter`. Returns 429.
- **Body limits:** All request bodies capped at 1MB via `httpx.LimitBodySize` middleware.
- **HTTP client:** Use `httpx.DefaultClient` (10s timeout) for outbound HTTP — never `http.DefaultClient`.

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
- Use `httpx.DefaultClient` for outbound HTTP — never `http.DefaultClient`
- Apply `httpx.LimitBodySize(1<<20)` to all JSON endpoints — 1MB cap
- Cap user-supplied strings (search, filters) at 255 chars
- **Testing:** see [docs/runbook/testing.md](./docs/runbook/testing.md). Coverage threshold: 50% minimum. Handler tests mock store interfaces (no DB). Run `make test-v` before every PR.

**TypeScript:**
- Strict mode, no `any`
- All API calls through `web/src/lib/api.ts` — never raw `fetch()` in components or hooks
- Server state via TanStack Query (`@tanstack/react-query` v5) — use `useQuery`/`useMutation`; never hand-roll `useState`+`useEffect` for API calls. Query keys in `web/src/lib/queryKeys.ts`, client config in `web/src/lib/queryClient.ts`
- Hook conventions: `useGames(filters)`, `useGame(id)`, `useCollections()`, `useProfile()` — one hook per domain, exported from `web/src/hooks/`

**Swift (iOS):**
- See [ios/AGENTS.md](./ios/AGENTS.md) for full iOS conventions — @Observable, SwiftData, Keychain, URLSession async/await, xcodegen

## Git Workflow

```
feature/*
fix/*        →  dev  ──PR──▶  main
chore/*
refactor/*
```

- **Branch from `dev`**, never from `main`
- **Prefix rules:** use `feature/*`, `fix/*`, `chore/*`, or `refactor/*` — **never `claude/*`**
- All PRs target `dev`; `dev → main` is the release gate (branch protection enforced)
- Commit subject: imperative present tense, 50-char max (`fix: ...`, `add: ...`, `remove: ...`)
- All merges to `dev` and `main` require a PR + passing CI

## Boundaries

**Always:**
- Include `user_id` in every query on user-owned data — multi-tenancy enforced at SQL layer
- Use `pkg/shared/apierr` sentinels for all error paths
- Validate JWT in `services/api/internal/jwt/` middleware — never skip or trust forwarded headers from untrusted callers
- Run `make test-v` before opening a PR
- Define store interfaces per package — `Handler` depends on the interface, not concrete `*Store` (enables `httptest` handler tests without DB)

**Ask first:**
- Any change to `pkg/shared` exported types (`services/api` depends on it)
- Auth flow modifications (JWT expiry, Supabase config, refresh logic, JWKS)
- Running `supabase db push` — this writes to the hosted production database
- New external service integrations or third-party dependencies
- Schema changes (migrations in `services/api/migrations/`)
- Using `skip_migrations: true` on a prod deploy — only safe when the new code is schema-compatible with the current DB

**Never:**
- Push directly to `main` or `dev`
- Query user-owned data without a `user_id` WHERE clause
- Expose raw `err.Error()` from DB or internal code to HTTP responses
- Commit secrets, `.env` files, or service account credentials
- Use `--no-verify` on commits
- Manually edit `.pbxproj` or `.xcodeproj/` in iOS app — hook prevents this by design. Use `xcodegen generate` in `ios/` directory instead

<!-- lean-ctx-compression -->
OUTPUT STYLE: dense
- Each statement = one atomic fact line
- Use abbreviations: fn, cfg, impl, deps, req, res, ctx, err, ret
- Diff lines only (+/-/~), never repeat unchanged code
- Symbols: → (causes), + (adds), − (removes), ~ (modifies), ∴ (therefore)
- No narration, no filler, no hedging
- BUDGET: ≤200 tokens per response unless code block required
<!-- /lean-ctx-compression -->
