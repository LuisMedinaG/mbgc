# AGENTS.md — mbgc monorepo

## Build & Test

```sh
# All services share the same per-service Makefile interface:
make dev       # go run ./cmd/server  (auto-loads .env)
make build     # CGO_ENABLED=0 go build -ldflags="-s -w" -o server ./cmd/server
make test      # go test ./...
make test-v    # go test -v -race ./...  ← use before every PR
make lint      # go vet ./...
make tidy      # go mod tidy

# Services with Postgres migrations (auth, game, importer):
make migrate-up
make migrate-down

# Web (from web/):
bun run dev
bun run build        # tsc -b && vite build
bun run lint
bun run test:e2e     # Playwright — requires full stack running
```

## go.work Workspace

`go.work` + `replace github.com/LuisMedinaG/mbgc/pkg/shared v0.0.0 => ./pkg/shared` means all services resolve `pkg/shared` locally — no version bump needed during development. Changes to `pkg/shared` are immediately visible to all services.

When touching `pkg/shared`: run `make tidy` and `make test-v` in each consuming service before opening a PR.

## Code Style (non-obvious rules)

**Go:**
- `slog` for structured logging — never `log.Printf` or `fmt.Println`
- Wrap errors with `fmt.Errorf("%w", err)`; check with `errors.Is` / `errors.As`
- Use `pkg/shared/apierr` sentinels — never expose raw `err.Error()` to HTTP clients
- Use `pkg/shared/httpx.WriteJSON` / `WriteError` — never `json.NewEncoder(w).Encode` directly
- Extract user identity via `httpx.UserIDFromContext` — the gateway injects `X-User-ID`, `X-Is-Admin` headers

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
- Trust gateway-forwarded headers (`X-User-ID`, `X-Is-Admin`) in downstream services — never re-validate the JWT there
- Run `make test-v` before opening a PR

**Ask first:**
- Schema changes affecting multiple services
- Any change to `pkg/shared` exported types (all 5 services depend on it)
- Auth flow modifications (JWT expiry, Supabase config, refresh logic)
- New external service integrations or third-party dependencies

**Never:**
- Push directly to `main` or `staging`
- Query user-owned data without a `user_id` WHERE clause
- Expose raw `err.Error()` from DB or internal code to HTTP responses
- Commit secrets, `.env` files, or service account credentials
- Use `--no-verify` on commits
