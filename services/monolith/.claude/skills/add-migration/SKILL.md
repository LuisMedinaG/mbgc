---
name: add-migration
description: Add a SQLite schema migration (new table or new column). Use when asked to add/alter database schema.
---

# Add Migration

All migrations live in `shared/db/db.go`. They run on every startup and must be idempotent.

## New table → add to `createTables()` stmts slice

```go
// shared/db/db.go — inside createTables(), in the stmts slice
`CREATE TABLE IF NOT EXISTS things (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name       TEXT    NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id, name)
)`,
```

If the table has a join/pivot table, add it right after:

```go
`CREATE TABLE IF NOT EXISTS game_things (
    game_id  INTEGER NOT NULL REFERENCES games(id)  ON DELETE CASCADE,
    thing_id INTEGER NOT NULL REFERENCES things(id) ON DELETE CASCADE,
    PRIMARY KEY (game_id, thing_id)
)`,
```

## New column on existing table → add to `addCols` slice

```go
// shared/db/db.go — in the addCols slice inside createTables()
// SQLite ignores "duplicate column" errors, so _, _ = discard is correct.
"ALTER TABLE games ADD COLUMN new_field TEXT NOT NULL DEFAULT ''",
```

Errors are intentionally discarded (`_, _ = db.Exec(s)`) — SQLite returns an error for duplicate
columns which is the expected idempotency signal. Do not change this pattern.

## After adding the schema

1. **Update the store's column list** — e.g. `gameColumns` const in `services/games/store.go`
2. **Update the scan function** — add the new field to `scanGame()` (or equivalent)
3. **Update the model struct** — `internal/model/game.go` (or relevant model file)
4. **Update `gameToAPI()`** — include the field in the JSON response map
5. **Run the app** to verify the migration applies cleanly: `make run`

## Checklist

- [ ] New table uses `CREATE TABLE IF NOT EXISTS`
- [ ] New column uses `ALTER TABLE … ADD COLUMN … DEFAULT …` in `addCols`
- [ ] Error discarded with `_, _ = db.Exec(s)` for addCols (not `if err != nil`)
- [ ] Column list constant updated in store.go
- [ ] Scan function updated
- [ ] Model struct updated
- [ ] API response map updated
- [ ] `make run` confirms clean startup (no panic)
