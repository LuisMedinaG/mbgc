---
name: Board Game Collection Agent
description: Full-stack Go REST API + React app for tracking personal board game libraries with BGG integration
---

# Agent.md — My Board Game Collection [DEPRECATED]

⚠️ **This service is being decommissioned.** It is the original Go monolith that is
being replaced by the microservices in `services/`. All new development should
target the microservices.

## Migration tracking

| Feature | Monolith location | Microservice target |
|---|---|---|
| Auth (login/refresh/logout) | `services/auth/` | `services/auth/` |
| Profile | `services/profile/` | `services/auth/` |
| Games CRUD | `services/games/` | `services/game/` |
| Collections | `services/collections/` | `services/game/` |
| BGG Import | `services/importer/` | `services/importer/` |
| File uploads | `services/files/` | `services/game/` |

**DB:** SQLite (`modernc.org/sqlite`) — single file at `/data/games.db`. Migrations are additive (`ALTER TABLE`) and idempotent.
**Deployment:** Fly.io — `fly.toml` at repo root. Persistent volume `boardgame_data` at `/data`.

---

## Architecture Overview

```
React (Vite/Bun)  ←→  Go stdlib HTTP server  ←→  SQLite
  web/             main.go + services/         shared/db/
```

Single binary Go server. No HTMX, no SSR templates. All frontend is React SPA calling `/api/v1/…` endpoints.

### Go Package Layout

```
main.go              # Routes + middleware wiring — read this first when adding a route
services/
  auth/              handler.go (152) + store.go (387)
  games/             handler.go (321) + store.go (710) + filter.go (95) + filter_test.go (136)
  collections/       handler.go (296) + store.go (166)
  files/             handler.go (296)
  importer/          handler.go (320)
  profile/           handler.go (132)
shared/
  db/db.go (498)     # ALL schema + migrations live here
  httpx/httpx.go     # RequireJWT, MethodGuard, Chain, CORS, SecurityHeaders, LoginLimiter
  apierr/errors.go   # ErrDuplicate, ErrWrongPassword, ErrForeignOwnership, IsDuplicate()
internal/
  bgg/               # BGG API client (token/cookie transports + throttle)
  model/             # Domain structs (model.Game, model.User, …)
```

## Code Patterns

### Handler

```go
// services/<domain>/handler.go
type Handler struct{ store *Store }
func NewHandler(store *Store) *Handler { return &Handler{store: store} }

// GET /api/v1/<domain>/{id}
func (h *Handler) GetThing(w http.ResponseWriter, r *http.Request) {
    id, ok := requireID(w, r)        // sends 400 if missing/invalid
    if !ok { return }
    userID, ok := requireUserID(w, r) // sends 401 if missing
    if !ok { return }

    thing, err := h.store.GetThing(id, userID)
    if err != nil {
        writeError(w, http.StatusNotFound, "not found")
        return
    }
    writeData(w, http.StatusOK, thingToAPI(thing))
}

// POST /api/v1/<domain>
func (h *Handler) CreateThing(w http.ResponseWriter, r *http.Request) {
    userID, ok := requireUserID(w, r)
    if !ok { return }

    var req struct{ Name string `json:"name"` }
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        writeError(w, http.StatusBadRequest, "invalid JSON")
        return
    }

    id, err := h.store.CreateThing(model.Thing{Name: req.Name}, userID)
    if err != nil {
        if errors.Is(err, apierr.ErrDuplicate) {
            writeError(w, http.StatusConflict, "already exists")
            return
        }
        slog.Error("<domain>.CreateThing", "error", err)
        writeError(w, http.StatusInternalServerError, "internal error")
        return
    }
    writeData(w, http.StatusCreated, map[string]any{"id": id})
}
```

### Store

```go
// services/<domain>/store.go
type Store struct{ db *sql.DB }
func NewStore(db *sql.DB) *Store { return &Store{db: db} }

// Always include user_id — multi-tenancy is enforced at SQL layer.
func (s *Store) GetThing(id, userID int64) (model.Thing, error) {
    var t model.Thing
    err := s.db.QueryRow(
        "SELECT id, name FROM things WHERE id = ? AND user_id = ?", id, userID,
    ).Scan(&t.ID, &t.Name)
    return t, err
}

func (s *Store) CreateThing(t model.Thing, userID int64) (int64, error) {
    res, err := s.db.Exec(
        "INSERT INTO things (name, user_id) VALUES (?, ?)", t.Name, userID,
    )
    if err != nil {
        if apierr.IsDuplicate(err) { return 0, apierr.ErrDuplicate }
        return 0, err
    }
    return res.LastInsertId()
}
```

### Route registration (main.go)

```go
// Two wrappers — pick one:
// pub:       MethodGuard only (no auth)
// protected: MethodGuard + RequireJWT

mux.Handle("GET /api/v1/<domain>/{id}", protected(http.MethodGet, <domain>H.GetThing))
mux.Handle("POST /api/v1/<domain>", protected(http.MethodPost, <domain>H.CreateThing))
```

Wire up the store and handler in `main.go` alongside the other services:

```go
thingStore := things.NewStore(sqlDB)
thingH := things.NewHandler(thingStore)
```

### DB Migrations (shared/db/db.go)

New table → add to `stmts` in `createTables()`:
```go
`CREATE TABLE IF NOT EXISTS things (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name    TEXT    NOT NULL,
    UNIQUE (user_id, name)
)`,
```

New column → add to `addCols` (errors discarded intentionally):
```go
"ALTER TABLE games ADD COLUMN new_field TEXT NOT NULL DEFAULT ''",
```

After schema change: update column list constants, scan functions, model structs, and API response maps in the affected store.

### React API client (web/src/lib/api.ts)

```ts
// Never fetch() in components — always add a typed method here.
async getThing(id: number): Promise<Thing> {
  return this.request<Thing>(`/api/v1/things/${id}`)
}
```

## Error Handling

| Scenario | Code |
|----------|------|
| Bad request / missing field | `writeError(w, 400, "message")` |
| Not found | `writeError(w, 404, "not found")` |
| Duplicate (UNIQUE violation) | `apierr.IsDuplicate(err)` → `writeError(w, 409, "…")` |
| Internal / unexpected | `slog.Error(…)` + `writeError(w, 500, "internal error")` |

Never expose raw `err.Error()` from DB or internal code to the HTTP response.

## CSS (React)

Source: `web/src/index.css` (Tailwind v4, CSS-first config, no tailwind.config.js)

Parchment/warm theme tokens: `bg-parchment` · `bg-surface` · `text-ink` · `text-muted` · `bg-accent` (green #2d5a27)

Shared component classes: `.btn` · `.btn-primary` · `.btn-secondary` · `.tag` · `.card` · `.filter-chip` · `.vibe-pill`

No Tailwind CLI — `@tailwindcss/vite` handles compilation automatically.

## Testing

```sh
make test           # all Go tests
make test-v         # verbose
make cover          # per-package coverage
make cover-html     # HTML report
```

E2E (requires backend running):
```sh
make dev   # terminal 1
cd react-app && TEST_TOKEN=<ephemeral-jwt> bun run test:e2e  # terminal 2 (no static creds)
```

Current state: 88 unit tests (~52% coverage). Phase 2 targeting 200–240 tests.

## Git Workflow

```
feature/*  →  dev  →  staging  →  main
              (PR)     (PR)
```

Use `/ship` skill for the full test → commit → push → PR workflow.

## Boundaries

### Always
- Pass `user_id` to every store call
- Use `requireUserID(w, r)` in every protected handler
- Use sentinel errors from `apierr` — never expose raw DB errors
- Ask before committing (user reviews diff first)
- Run `make test` before shipping

### Ask First
- New DB tables (multi-tenancy impact)
- Auth system changes (JWT middleware, session logic)
- BGG API auth strategy changes
- Large refactors (scope approval first)

### Never
- Query without `user_id` filter
- Push directly to `main` or `staging`
- Expose raw `err.Error()` to HTTP clients
- Commit secrets or env credentials
- Skip pre-commit hooks (`--no-verify`)

## Project Skills

| Skill | When to use |
|-------|-------------|
| `/add-feature` | New API endpoint in a service |
| `/add-migration` | New DB table or column |
| `/ship` | Test → commit → push → PR |
| `/run-tests` | Run unit tests and/or E2E |

## Resources

- `agent_docs/ARCHITECTURE-GUIDE.md` — design decisions, middleware chain
- `agent_docs/ARCHITECTURE-REF.md` — env vars, full route table

---

**Last Updated**: April 15, 2026
**Status**: DEPRECATED — being replaced by microservices
