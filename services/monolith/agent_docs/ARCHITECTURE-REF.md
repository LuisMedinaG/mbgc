# Quick Reference

## Environment Variables

| Variable | Default | Notes |
|----------|---------|-------|
| `PORT` | `8080` | HTTP listen port |
| `DB_PATH` | `games.db` | SQLite file path |
| `DATA_DIR` | `data` | Uploads + image cache |
| `SESSION_SECRET` | — | JWT signing key; required in prod (⚠️ verify set on Fly) |
| `BGG_TOKEN` | — | Primary BGG auth (takes priority over cookie) |
| `BGG_COOKIE` | — | Fallback when no token set |
| `REACT_ORIGIN` | `http://localhost:5173` | Allowed CORS origin for React dev server |

## Routes

| Method | Path | Service | Notes |
|--------|------|---------|-------|
| POST | `/api/v1/auth/login` | auth | Public |
| POST | `/api/v1/auth/refresh` | auth | Public |
| POST | `/api/v1/auth/logout` | auth | Public |
| GET | `/api/v1/ping` | auth | Protected |
| GET | `/api/v1/games` | games | Protected; server-side filtering via query params |
| GET | `/api/v1/games/{id}` | games | Protected |
| DELETE | `/api/v1/games/{id}` | games | Protected |
| POST | `/api/v1/games/{id}/collections` | games | Protected |
| POST | `/api/v1/games/bulk-collections` | games | Protected |
| GET | `/api/v1/collections` | collections | Protected |
| POST | `/api/v1/collections` | collections | Protected |
| PUT | `/api/v1/collections/{id}` | collections | Protected |
| DELETE | `/api/v1/collections/{id}` | collections | Protected |
| GET | `/api/v1/discover` | collections | Protected |
| POST | `/api/v1/import/sync` | importer | Protected; BGG sync |
| POST | `/api/v1/import/csv/preview` | importer | Protected |
| POST | `/api/v1/import/csv` | importer | Protected |
| GET | `/api/v1/profile` | profile | Protected |
| PUT | `/api/v1/profile/bgg-username` | profile | Protected |
| PUT | `/api/v1/profile/password` | profile | Protected |
| PUT | `/api/v1/games/{id}/rules-url` | files | Protected |
| POST | `/api/v1/games/{id}/player-aids` | files | Protected; multipart upload |
| DELETE | `/api/v1/games/{id}/player-aids/{aid_id}` | files | Protected |
| GET | `/uploads/*` | static | Player aid images from disk |

## DB Schema (key tables)

```sql
users       (id, username, bgg_username, password_hash, email, is_admin, …)
sessions    (token, user_id, expires_at, kind)           -- kind='refresh' for JWT refresh tokens
games       (id, user_id, bgg_id, name, weight, rating, …)
collections (id, user_id, name, description)
collection_games (collection_id, game_id)
player_aids (id, game_id, filename, label)
categories / mechanics / game_categories / game_mechanics  -- normalized for filtering
games_fts   -- FTS5 virtual table (name, description); kept in sync via triggers
```
