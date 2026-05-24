# mbgc-game-service

Core domain service — owns everything about games, collections, and files.
Extracted from the monolith (`services/monolith`); mirrors its data model.

## Stack

- **Language:** Go 1.25
- **DB:** Postgres via Supabase (`github.com/jackc/pgx/v5`)
- **Shared:** `github.com/LuisMedinaG/mbgc/pkg/shared`

## Game Model — Key Fields

| Field | Type | DB column | Source |
|---|---|---|---|
| `Weight` | `float64` | `weight` | BGG `averageweight` |
| `Rating` | `float64` | `rating` | BGG `average` |
| `LanguageDependence` | `int` | `language_dependence` | BGG poll winner (0=unknown, 1–5) |
| `RecommendedPlayers` | `[]int` | `recommended_players` | BGG poll — array of counts |

## Filters

All filters flow through query parameters on list endpoints:

| Param | Values |
|---|---|
| `search` | Full-text search (tsvector) |
| `category` | Category filter |
| `page` | Page number (default 1) |
| `limit` | Page size (default 20) |

## DB Schema

Tables in `games` schema:
- `games.games` — core game data with FTS (tsvector)
- `games.collections` — user-defined game groups ("vibes")
- `games.collection_games` — M:N junction
- `games.player_aids` — uploaded files per game

## API surface (mounted under `/api/v1/games/*` etc. at the gateway)

Standard CRUD for games, collections, player aids, and file uploads.
All list endpoints support pagination and filters.

## Commands

```sh
make dev
make test
make migrate-up
make migrate-down
```

## Deployment

GCP Cloud Run — deployed via GitHub Actions CI/CD.
Database URL injected as secret.

<claude-mem-context>
</claude-mem-context>
