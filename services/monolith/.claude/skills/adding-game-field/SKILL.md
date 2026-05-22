---
name: adding-game-field
description: Adds a new column to the games table in this Go+SQLite board game app, wiring it through the model, schema migration, BGG import, store I/O, and the API converter. Use when the user asks to add a game attribute or BGG field (e.g. "add min-age", "store the publisher"), when adding any column to the games table, or when backfilling BGG metadata onto existing games.
---

# Adding a field to the games table

Every new column on `games` touches five places. Miss any one and the schema, store, BGG import, or API response will disagree.

## Required touch points

```
- [ ] 1. internal/model/model.go        — add field to Game struct
- [ ] 2. shared/db/db.go                — append ALTER to addCols (and CREATE TABLE for fresh DBs)
- [ ] 3. services/games/store.go        — gameColumns const + scanGame + CreateGame + UpdateGame
- [ ] 4. internal/bgg/bgg.go            — populate in bggItemToGame (if BGG-sourced)
- [ ] 5. services/games/handler.go      — gameToAPI snake_case mapping
- [ ] 6. Call out Full Refresh if backfilling existing BGG-sourced rows
```

## Step 1 — Model

Add the field to the `Game` struct in `internal/model/model.go`. Go name is PascalCase; keep alignment with the surrounding BGG-sourced block:

```go
Weight             float64
Rating             float64
LanguageDependence int
RecommendedPlayers string
MyNewField         T      // one-line comment only if the WHY is non-obvious
```

## Step 2 — Schema migration

All schema work lives in `shared/db/db.go`. Migrations run on every startup and must be idempotent. See also the `/add-migration` skill.

**New column** — append to the `addCols` slice inside `createTables()`:

```go
// shared/db/db.go — inside createTables(), in addCols
"ALTER TABLE games ADD COLUMN my_new_field TYPE NOT NULL DEFAULT default_value",
```

Rules:
- Always `NOT NULL DEFAULT …` — no nullable columns.
- Errors are intentionally discarded (`_, _ = db.Exec(s)`). SQLite returns an error when the column already exists; that's the idempotency signal. Do not change this pattern.
- DB column is snake_case; Go field is PascalCase.

Also add the column to the `CREATE TABLE games (…)` statement in `createTables()` stmts so fresh DBs pick it up without the ALTER step.

## Step 3 — Store (read + write)

In `services/games/store.go`:

1. **`gameColumns` const** — append the new column to the SELECT list (order matters).
2. **`scanGame`** — append `&g.MyNewField` in the exact same order as `gameColumns`.
3. **`CreateGame`** — add the column to `INSERT INTO games (...)`, add a `?` to `VALUES (...)`, and pass `g.MyNewField` to `db.Exec`.
4. **`UpdateGame`** — add `my_new_field=?` to the `SET` list and pass `g.MyNewField`.

If you add a new query that projects `gameColumns` with a table alias (e.g. `g.`), use the full list; don't hand-roll another SELECT.

## Step 4 — BGG mapping (if applicable)

If the field comes from BGG, populate it in `bggItemToGame` in `internal/bgg/bgg.go`.

- **Stat** (e.g. BGG rank, owners): extend `bggRatingsXML` / `bggStatisticsXML` with a new `bggSimpleAttr` or nested struct, then set on the Game.
- **Poll** (e.g. "suggested player age"): add a `parseXxx(polls []bggPollXML) T` helper next to `parseLanguageDependence` / `parseRecommendedPlayers`. Match by `p.Name == "bgg_poll_name"`.
- **Link** (designers, artists — `boardgame<type>` link elements): add a `case "boardgame<type>":` branch in the `item.Link` loop, collect into a slice, then `strings.Join(x, ", ")`.

Poll conventions: treat missing polls or zero votes as zero values; don't error. For ranked polls, pick the option with the most votes. Strip `"+"` suffixes from player counts.

See the `/importing-from-bgg` skill if you're adding a new BGG endpoint rather than a new field.

## Step 5 — API response

In `services/games/handler.go`, add the field to `gameToAPI` with a snake_case JSON key:

```go
"my_new_field": g.MyNewField,
```

`gameToAPI` is the only converter; every handler that returns a game goes through it.

## Step 6 — Backfill warning (BGG-sourced only)

Normal BGG sync skips games the user already owns, so existing rows keep the default value forever. Tell the user:

> To backfill existing games, run a Full Refresh: check the "Full Refresh" box on the Import page (admin-only), or `POST /api/v1/import` with `{"full_refresh": true}`.

## Verification

```sh
make build   # catches type mismatches in model / store / BGG
make test    # exercises the store and migrations
make run     # confirms the migration applies cleanly on startup
```

See also: `/adding-game-filter` to expose the new field as a filter, `/importing-from-bgg` for BGG-specific work.
