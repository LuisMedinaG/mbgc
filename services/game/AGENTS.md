# AGENTS.md — services/game

Core domain: games, collections, player aids, file uploads. Postgres via Supabase (`games` schema).

## Commands

```sh
make dev          # loads .env; listens on :8002
make test-v       # go test -v -race ./...
make migrate-up
make migrate-down
```

## Patterns

- All tables live in the `games` Postgres schema (not `public`) — qualify queries as `games.games`, `games.collections`, etc.
- Full-text search via `tsvector` column on `games.games` — when adding a searchable column, update the FTS trigger in the migration
- File uploads: multipart → Supabase Storage; record the storage path in `player_aids`, return a signed URL (never serve the file directly)
- All list endpoints must support `page` + `limit` query params and return `{ data: [...], meta: { page, limit, total } }`

## Boundaries

**Ask first:**
- Adding columns to `games.games` — the FTS trigger must be kept in sync
- Changing the storage path scheme for uploaded files

**Never:**
- Make BGG API calls — that is services/importer
- Serve file bytes directly — always return a signed Supabase Storage URL
- Accept writes without a `user_id` check
