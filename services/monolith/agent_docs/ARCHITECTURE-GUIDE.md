# Architecture Guide

Read this when you need to understand *why* things are built this way — not *how* (read the code for that).

## Macro Architecture

```
React SPA (Vite/Bun)
    ↕ /api/v1/* (JSON, JWT)
Go stdlib HTTP server (main.go)
    ↕
services/<domain>/ (handler + store per domain)
    ↕
SQLite (shared/db/db.go — schema + migrations)
```

Single Go binary. No HTMX, no SSR templates. The React SPA handles all UI; Go is a pure REST API.

## Request Pipeline

```
Request
  → httpx.SecurityHeaders()
  → httpx.CORS(reactOrigin)
  → httpx.MethodGuard(method)      [via pub() or protected()]
  → httpx.RequireJWT(secret)       [protected() only]
  → Handler
```

`httpx.Chain(handler, A, B, C)` reverses internally so A runs first. Read the `mux.Handle` line in `main.go` to see the stack in natural order.

## Design Decisions That Affect How You Code

| Decision | What it means for you |
|---|---|
| Domain-per-service layout | Each `services/<domain>/` owns its own handler.go + store.go. Don't reach across domain boundaries. |
| JWT-only auth | No session cookies. Every protected route requires `httpx.RequireJWT`. Extract user ID with `requireUserID(w, r)`. |
| `user_id` in every query | Multi-tenancy at SQL layer. Never write a query without passing `userID`. |
| Migrations in `shared/db/db.go` | Idempotent, run on startup. New tables → `createTables()`. New columns → `addCols` slice (errors silently discarded = idempotent). |
| `apierr` sentinel errors | `IsDuplicate(err)` for UNIQUE violations. Sentinel vars for domain errors. Never expose raw DB errors. |
| FTS5 for search | Triggers keep `games_fts` in sync. Don't bypass them with direct inserts. |
| BGG three-layer transport | auth → throttle → network (inside `internal/bgg/`). Don't add manual sleeps or retry logic around BGG calls. |
| `shared/` for cross-cutting code | `db`, `httpx`, `apierr` are used by all services. Changes here affect everything. |
| React owns all UI | No Go templates. Don't add HTML rendering to the Go server. |
