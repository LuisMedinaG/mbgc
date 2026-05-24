# mbgc-importer-service

Handles all external data ingestion: BGG collection sync and CSV import.
Extracted from the monolith; shares the same BGG client approach.

## Stack

- **Language:** Go 1.25
- **BGG client:** Custom XML fetch — throttled, authenticated
- **Shared:** `github.com/LuisMedinaG/mbgc/pkg/shared`

## Sync modes

| Mode | Trigger | Scope |
|---|---|---|
| **Incremental** | Normal sync | Newly added games only |
| **Full Refresh** | Admin-only | Backfills `weight`, `rating`, `language_dependence`, `recommended_players` |

## Rate limiting

Daily sync quotas per user:
- Regular users: 3 syncs/day (configurable via `SYNC_LIMIT_USER`)
- Admins: 20 syncs/day (configurable via `SYNC_LIMIT_ADMIN`)

## API surface (mounted under `/api/v1/import/*` at the gateway)

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v1/import/sync` | Trigger BGG sync (`full_refresh` flag for admins) |
| `POST` | `/api/v1/import/csv/preview` | Preview CSV import |
| `POST` | `/api/v1/import/csv` | Import games from CSV |

## Key env vars

| Var | Purpose |
|---|---|
| `DATABASE_URL` | Supabase Postgres connection string |
| `GAME_SERVICE_URL` | Internal URL of services/game |
| `BGG_TOKEN` | BGG API token (optional) |
| `BGG_COOKIE` | BGG session cookie (optional) |

## Commands

```sh
make dev
make test
make migrate-up
make migrate-down
```

## Deployment

GCP Cloud Run — deployed via GitHub Actions CI/CD.
Database URL and BGG credentials injected as secrets.

<claude-mem-context>
</claude-mem-context>
