---
name: add-endpoint
description: Add a new API endpoint to a Go microservice (auth, game, importer). Use when asked to add a new route, handler, or backend capability.
---

# Add Endpoint

## Architecture per service

```
services/<name>/
  cmd/server/main.go        # route registration, server wiring
  handler.go                # HTTP handlers (or internal/handler/)
  internal/store/store.go   # DB queries (pgx/v5)
  internal/model/           # domain structs
```

## Step 1: Store method

Use `pgxpool.Pool`, `$1`/`$2` Postgres placeholders, named schemas. Always filter by `user_id`.

```go
func (s *Store) GetThing(ctx context.Context, id int64, userID string) (*model.Thing, error) {
    row := s.db.QueryRow(ctx,
        `SELECT id, user_id, name, created_at FROM <schema>.things
         WHERE id = $1 AND user_id = $2`, id, userID)
    var t model.Thing
    if err := row.Scan(&t.ID, &t.UserID, &t.Name, &t.CreatedAt); err != nil {
        return nil, err
    }
    return &t, nil
}

func (s *Store) CreateThing(ctx context.Context, userID, name string) (*model.Thing, error) {
    row := s.db.QueryRow(ctx,
        `INSERT INTO <schema>.things (user_id, name) VALUES ($1, $2)
         RETURNING id, user_id, name, created_at`, userID, name)
    var t model.Thing
    if err := row.Scan(&t.ID, &t.UserID, &t.Name, &t.CreatedAt); err != nil {
        return nil, err
    }
    return &t, nil
}
```

## Step 2: Handler method

Read user identity from gateway-injected headers — never re-validate the JWT.

```go
func (h *Handler) GetThing(w http.ResponseWriter, r *http.Request) {
    userID := r.Header.Get("X-User-ID")
    if userID == "" {
        httpx.WriteError(w, http.StatusUnauthorized, apierr.ErrUnauthorized)
        return
    }
    id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
    if err != nil {
        httpx.WriteError(w, http.StatusBadRequest, apierr.ErrBadRequest)
        return
    }
    thing, err := h.store.GetThing(r.Context(), id, userID)
    if err != nil {
        httpx.WriteError(w, http.StatusNotFound, apierr.ErrNotFound)
        return
    }
    httpx.WriteJSON(w, http.StatusOK, thingToAPI(thing))
}
```

## Step 3: Route registration (main.go)

```go
// Protected (JWT required — gateway enforces, service trusts headers)
mux.HandleFunc("GET /api/v1/things/{id}", h.GetThing)
mux.HandleFunc("POST /api/v1/things",     h.CreateThing)
mux.HandleFunc("DELETE /api/v1/things/{id}", h.DeleteThing)
```

## Step 4: Gateway routing (if new path prefix)

If this is a brand-new path prefix not yet proxied, add it to `services/gateway/cmd/server/main.go` routing table.

## Response format

```go
// Success
httpx.WriteJSON(w, http.StatusOK, envelope{"data": payload})

// Error — use apierr sentinels, never raw err.Error()
httpx.WriteError(w, http.StatusNotFound, apierr.ErrNotFound)
```

## Checklist

- [ ] `user_id` in every DB query — no cross-tenant data leaks
- [ ] Use `apierr` sentinels — never expose raw DB errors
- [ ] Use `httpx.WriteJSON` / `httpx.WriteError` — never `json.NewEncoder`
- [ ] Read identity from `X-User-ID` / `X-Is-Admin` headers — never re-validate JWT
- [ ] `make test-v` passes
