---
name: adding-game-filter
description: Adds a new game-list filter (query param, SQL condition, handler plumbing) to this Go+SQLite board game app. Use when the user asks to filter games by some attribute, expose a new filter URL param on /api/v1/games or /api/v1/discover, or add a filter chip that the React frontend can render.
---

# Adding a game filter

Filters are parameterized SQL fragments plus a thin fan-out through the store and two handlers. Existing filters (`players`, `playtime`, `weight`, `rating`, `lang`, `rec_players`) all follow the same shape.

> The React frontend lives in a separate repo (`mbgc-web`). This skill covers the Go API only — UI wiring is out of scope.

## Required touch points

```
- [ ] 1. services/games/filter.go        — add XxxCondition(value, prefix) returning a SQL fragment
- [ ] 2. services/games/store.go         — wire into buildGameConditions + FilterGames signature
- [ ] 3. services/games/store.go         — wire into FilterGamesByCollection signature
- [ ] 4. services/games/handler.go       — read r.URL.Query().Get("xxx") in ListGames
- [ ] 5. services/collections/handler.go — read the same param in Discover
```

## Step 1 — SQL condition

Conditions live in `services/games/filter.go`. Each returns a parenthesis-free SQL fragment, or `""` when the param is empty or invalid. The `prefix` argument supports unaliased queries (`""`) and aliased queries (`"g."` from `FilterGamesByCollection`).

**For enum-like filters** (e.g. `weight`, `rating`) use a `switch`:

```go
func XxxCondition(xxx, prefix string) string {
    switch xxx {
    case "low":  return prefix + "xxx < 2.0"
    case "high": return prefix + "xxx >= 3.0"
    default:     return ""
    }
}
```

**For filters that embed a validated literal in SQL** (needed when `?` placeholders can't be used — e.g. LIKE-wrapped constants), follow `RecommendedPlayersCondition` exactly: validate every character first and reject anything unexpected.

```go
for _, ch := range count {
    if ch < '0' || ch > '9' {
        return ""
    }
}
return "',' || " + prefix + "recommended_players || ',' LIKE '%," + count + ",%'"
```

Never concatenate user input into SQL without a char-by-char allowlist. If the values are enum-like, a `switch` is safer.

## Step 2 — buildGameConditions + FilterGames

`buildGameConditions` in `services/games/store.go` aggregates filter SQL for `FilterGames`. Append:

```go
if cond := XxxCondition(xxx, ""); cond != "" {
    conditions = append(conditions, cond)
}
```

`FilterGames` takes filter values as positional string params. Thread the new one through its signature, keeping the order aligned with `buildGameConditions`. Current signature:

```go
func (s *Store) FilterGames(
    q, category, players, playtime, weight, rating, lang, recPlayers string,
    page, pageSize int,
    userID int64,
) ([]model.Game, int, error)
```

The compiler will find every call site, but the order must match caller and callee exactly.

## Step 3 — FilterGamesByCollection

`FilterGamesByCollection` is a separate function with its own conditions block (it joins `game_collections` and uses the `"g."` prefix). Add the same wiring there. Current signature:

```go
func (s *Store) FilterGamesByCollection(
    collectionID int64,
    typ, category, mechanic, players, playtime, weight, rating, lang, recPlayers string,
    userID int64,
) ([]model.Game, error)
```

## Step 4 — Games handler

`services/games/handler.go` → `ListGames` reads query params and calls `FilterGames`. Keep variable naming consistent (`xxx := r.URL.Query().Get("xxx")`).

## Step 5 — Collections handler

`services/collections/handler.go` → `Discover` reads the same params and calls `FilterGamesByCollection` (this is the endpoint behind vibe-style discovery).

## URL param naming

Keep param names short and lowercase (`players`, `playtime`, `weight`, `rating`, `lang`, `rec_players`). Use underscores when disambiguation helps. Don't rename existing params — they're part of the REST API contract with `mbgc-web`.

## Verification

```sh
make test
# Manual:
TOKEN=$(...)
curl "localhost:8080/api/v1/games?xxx=low" -H "Authorization: Bearer $TOKEN"
curl "localhost:8080/api/v1/discover?collection_id=1&xxx=low" -H "Authorization: Bearer $TOKEN"
```

See also: `/adding-game-field` to add the underlying column, `/add-feature` for the general API-endpoint pattern.
