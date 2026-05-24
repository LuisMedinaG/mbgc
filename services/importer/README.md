# mbgc-importer-service

Handles BGG collection sync and CSV import. The only service that talks to the external BGG API.

## Routes

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/import/sync` | Sync BGG collection (rate limited: 3/day user, 20/day admin) |
| `POST` | `/api/v1/import/csv/preview` | Preview BGG CSV export (multipart, field: `csv_file`) |
| `POST` | `/api/v1/import/csv` | Import from BGG IDs (JSON: `{"bgg_ids": [...]}`) |

## Architecture

```
cmd/server/main.go
internal/
  config/config.go    ← env vars incl. BGG_TOKEN, sync limits
  bgg/client.go       ← BGG HTTP client (nil-safe, optional)
  handler/handler.go  ← HTTP layer with OpenAPI-style comments
  service/service.go  ← CSV parsing, BGG sync orchestration
  store/store.go      ← rate limiting + audit log
  model/model.go      ← SyncResult, CSVPreviewRow, RateLimit
migrations/
  001_init.up.sql     ← importer schema (rate_limits, sync_log)
deploy/
  Dockerfile
  fly.toml
```

## Cross-service calls

Importer calls **game-service** to create games (via HTTP, `GameClient` interface).
Importer reads BGG username from the `X-BGG-Username` header (to be injected by the gateway after enrichment from auth-service).

## Environment variables

| Var | Required | Default | Description |
|-----|----------|---------|-------------|
| `DATABASE_URL` | yes | — | Supabase Postgres |
| `GAME_SERVICE_URL` | no | `http://localhost:8002` | Internal game-service URL |
| `BGG_TOKEN` | no | — | BGG API token (primary) |
| `BGG_COOKIE` | no | — | BGG session cookie (fallback) |
| `SYNC_LIMIT_USER` | no | `3` | Daily sync limit for regular users |
| `SYNC_LIMIT_ADMIN` | no | `20` | Daily sync limit for admins |
| `PORT` | no | `8003` | Listen port |
