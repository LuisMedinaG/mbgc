# AGENTS.md — services/game

Core domain: games, collections, player aids, file uploads. Postgres via Supabase (`games` schema).

## Stack

- **Language:** Go 1.25
- **DB:** `github.com/jackc/pgx/v5` — all tables in `games` schema (not `public`)
- **Shared:** `github.com/LuisMedinaG/mbgc/pkg/shared`
- **Deployment:** GCP Cloud Run — `DATABASE_URL` injected as secret

## DB Schema

- `games.games` — core game data with FTS (tsvector)
- `games.collections` — user-defined game groups ("vibes")
- `games.collection_games` — M:N junction
- `games.player_aids` — uploaded files per game

## Game Model — Key Fields

| Field | Type | DB column | Source |
|---|---|---|---|
| `Weight` | `float64` | `weight` | BGG `averageweight` |
| `Rating` | `float64` | `rating` | BGG `average` |
| `LanguageDependence` | `int` | `language_dependence` | BGG poll winner (0=unknown, 1–5) |
| `RecommendedPlayers` | `[]int` | `recommended_players` | BGG poll — array of counts |

## List endpoint filters

| Param | Values |
|---|---|
| `search` | Full-text search (tsvector) |
| `category` | Category filter |
| `page` | Page number (default 1) |
| `limit` | Page size (default 20) |

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
