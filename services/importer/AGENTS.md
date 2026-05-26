# AGENTS.md — services/importer

External ingestion only: BGG XML sync and CSV import. Writes game data by calling services/game internal API — does not touch the games DB directly.

## Stack

- **Language:** Go 1.25
- **BGG client:** Custom XML fetch — throttled, authenticated
- **Shared:** `github.com/LuisMedinaG/mbgc/pkg/shared`
- **Deployment:** GCP Cloud Run — DB URL and BGG credentials injected as secrets

## API surface (mounted under `/api/v1/import/*` at gateway)

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v1/import/sync` | Trigger BGG sync (`full_refresh` flag for admins) |
| `POST` | `/api/v1/import/csv/preview` | Preview CSV import |
| `POST` | `/api/v1/import/csv` | Import games from CSV |

## Env vars

| Var | Purpose |
|---|---|
| `DATABASE_URL` | Supabase Postgres connection string |
| `GAME_SERVICE_URL` | Internal Cloud Run URL of services/game |
| `BGG_TOKEN` | BGG API token (optional) |
| `BGG_COOKIE` | BGG session cookie (optional) |
| `SYNC_LIMIT_USER` | Daily sync quota — regular users (default 3) |
| `SYNC_LIMIT_ADMIN` | Daily sync quota — admins (default 20) |

## Commands

```sh
make dev          # loads .env; listens on :8003
make test-v       # go test -v -race ./...
make migrate-up
make migrate-down
```

## Patterns

- Does not write to `games.games` directly — calls `GAME_SERVICE_URL` (internal Cloud Run URL)
- **Incremental sync:** new games only (normal user trigger)
- **Full refresh:** admin-only; backfills `weight`, `rating`, `language_dependence`, `recommended_players` for all existing games
- BGG XML API is rate-throttled in the client — never add unbounded loops or bypass the throttle
- Daily sync quotas: 3/day regular users, 20/day admins (env vars `SYNC_LIMIT_USER`, `SYNC_LIMIT_ADMIN`)

## Boundaries

**Never:**
- Bypass BGG rate limiting — will get the app IP banned
- Allow full refresh without verifying `X-Is-Admin` header

**Ask first:**
- Changing sync quota limits (affects all users)
- Adding new BGG data fields to the sync (requires a corresponding migration in services/game)
