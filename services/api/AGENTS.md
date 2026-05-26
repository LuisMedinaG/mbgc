# AGENTS.md — services/api

Single Go API service. Handles JWT validation, profiles, games, collections, and BGG import. Replaces the former gateway + auth + game + importer microservices.

## Stack

- **Language:** Go 1.25
- **Auth:** Supabase ES256/JWKS — `internal/jwt/verifier.go`
- **DB:** pgx/v5 + pgxpool → Supabase Postgres
- **Shared:** `github.com/LuisMedinaG/mbgc/pkg/shared`
- **Deployment:** GCP Cloud Run (`mbgc-api`) — build context is repo root

## API surface

| Method | Path | Handler |
|---|---|---|
| `GET` | `/api/v1/profile` | profile.GetProfile |
| `PUT` | `/api/v1/profile/bgg-username` | profile.SetBGGUsername |
| `GET` | `/api/v1/games` | game.ListGames |
| `GET` | `/api/v1/games/{id}` | game.GetGame |
| `DELETE` | `/api/v1/games/{id}` | game.DeleteGame |
| `POST` | `/api/v1/games/{id}/collections` | game.SetGameCollections |
| `POST` | `/api/v1/games/bulk-collections` | game.BulkCollections |
| `PUT` | `/api/v1/games/{id}/rules-url` | game.UpdateRulesURL |
| `POST` | `/api/v1/games/{id}/player-aids` | game.UploadPlayerAid |
| `DELETE` | `/api/v1/games/{id}/player-aids/{aid_id}` | game.DeletePlayerAid |
| `GET` | `/api/v1/collections` | game.ListCollections |
| `POST` | `/api/v1/collections` | game.CreateCollection |
| `PUT` | `/api/v1/collections/{id}` | game.UpdateCollection |
| `DELETE` | `/api/v1/collections/{id}` | game.DeleteCollection |
| `GET` | `/api/v1/discover` | game.Discover |
| `POST` | `/api/v1/import/sync` | importer.Sync |
| `POST` | `/api/v1/import/csv/preview` | importer.CSVPreview |
| `POST` | `/api/v1/import/csv` | importer.CSVImport |
| `GET` | `/healthz` | inline |

## Env vars

| Var | Required | Default | Purpose |
|---|---|---|---|
| `PORT` | No | `8080` | Listen port |
| `DATABASE_URL` | **Yes** | — | Postgres connection |
| `SUPABASE_URL` | **Yes** | — | JWKS endpoint base URL |
| `SUPABASE_JWT_SECRET` | No | — | Legacy HS256 fallback |
| `ALLOWED_ORIGIN` | No | — | CORS allowed origin |
| `BGG_TOKEN` | No | — | BGG API token |
| `BGG_COOKIE` | No | — | BGG session cookie |
| `SYNC_LIMIT_USER` | No | `3` | Daily BGG sync quota (regular users) |
| `SYNC_LIMIT_ADMIN` | No | `20` | Daily BGG sync quota (admins) |

## Commands

```sh
make dev          # loads .env; listens on :8080
make test-v       # go test -v -race ./...
make migrate-up   # applies all migrations in order
make migrate-down # reverts all migrations in reverse order
```

## Packages

```
internal/config/    — env var loading (mustenv panics on missing required vars)
internal/jwt/       — JWKS+HS256 verifier; RequireAuth middleware → httpx.SetGatewayUser
internal/profile/   — profile.users table (BGG username, admin flag)
internal/game/      — games.games, games.collections, games.player_aids tables
internal/importer/  — importer.rate_limits, importer.sync_log; BGG client
```

## Boundaries

**Always:**
- Include `user_id` in every DB query on user-owned data
- Use `httpx.UserIDFromContext` to get user identity — never read from headers directly
- Use `pkg/shared/apierr` sentinels for all error paths

**Never:**
- Bypass BGG rate limiting in `importer.Client` — will get IP banned
- Allow `full_refresh` sync without verifying `httpx.IsAdminFromContext`
- Expose raw `err.Error()` to HTTP responses

**Ask first:**
- Adding migrations (need to coordinate numbering: 001, 002, 003 are taken)
- Changing BGG sync quota defaults
- New third-party dependencies
