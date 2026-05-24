---
name: add-feature
description: Add a new API endpoint to a service domain. Use when asked to add a new route, handler, or backend capability.
---

# Add Feature

## Current Architecture

```
services/<domain>/
  handler.go   # HTTP handlers for all domain routes
  store.go     # All DB queries for the domain
main.go        # Route registration (protected/pub wrappers)
shared/
  apierr/      # Sentinel errors + helpers
  httpx/       # Middleware (RequireJWT, MethodGuard, Chain, CORS, SecurityHeaders)
  db/          # Schema + migrations (createTables, addCols)
internal/
  model/       # Domain structs shared across services
```

## Step 1: Store method (services/<domain>/store.go)

```go
// Always pass userID for multi-tenancy — never query without it.
func (s *Store) GetThing(id, userID int64) (model.Thing, error) {
    return scanThing(s.db.QueryRow(
        "SELECT "+thingColumns+" FROM things WHERE id = ? AND user_id = ?", id, userID,
    ))
}

func (s *Store) CreateThing(t model.Thing, userID int64) (int64, error) {
    res, err := s.db.Exec(
        `INSERT INTO things (name, user_id) VALUES (?, ?)`, t.Name, userID,
    )
    if err != nil {
        if apierr.IsDuplicate(err) {
            return 0, apierr.ErrDuplicate
        }
        return 0, err
    }
    return res.LastInsertId()
}
```

## Step 2: Handler method (services/<domain>/handler.go)

```go
// GET /api/v1/<domain>/{id}
func (h *Handler) GetThing(w http.ResponseWriter, r *http.Request) {
    id, ok := requireID(w, r)
    if !ok { return }
    userID, ok := requireUserID(w, r)
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

    var req struct {
        Name string `json:"name"`
    }
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        writeError(w, http.StatusBadRequest, "invalid JSON")
        return
    }
    if req.Name == "" {
        writeError(w, http.StatusBadRequest, "name is required")
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

## Step 3: Wire route in main.go

```go
// Protected (JWT required):
mux.Handle("GET /api/v1/<domain>/{id}", protected(http.MethodGet, <domain>H.GetThing))
mux.Handle("POST /api/v1/<domain>", protected(http.MethodPost, <domain>H.CreateThing))

// Public (no auth):
mux.Handle("POST /api/v1/<domain>/public-action", pub(http.MethodPost, <domain>H.PublicAction))
```

## Step 4: React API client (react-app/src/lib/api.ts)

If the React frontend needs to call this endpoint, add a typed method to api.ts:

```ts
// Never call fetch() directly in components — always go through api.ts.
async getThing(id: number): Promise<Thing> {
  return this.request<Thing>(`/api/v1/<domain>/${id}`)
}

async createThing(name: string): Promise<{ id: number }> {
  return this.request<{ id: number }>('/api/v1/<domain>', {
    method: 'POST',
    body: JSON.stringify({ name }),
  })
}
```

## Checklist

- [ ] `user_id` passed to every store method
- [ ] Sentinel errors used (`apierr.ErrDuplicate`, `apierr.ErrForeignOwnership`)
- [ ] Handler uses `requireUserID()` and `requireID()` helpers
- [ ] Route registered in main.go under correct HTTP method
- [ ] `slog.Error()` for unexpected errors (never expose raw DB errors)
- [ ] React api.ts updated if frontend needs the endpoint
- [ ] Run `make test` before shipping
