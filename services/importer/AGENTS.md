# AGENTS.md — services/importer

External ingestion only: BGG XML sync and CSV import. Writes game data by calling services/game internal API — does not touch the games DB directly.

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
