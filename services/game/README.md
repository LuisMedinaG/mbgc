# mbgc-game-service

Core domain service. Owns games, collections, player aids, and file uploads.

## Routes

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/games` | List games (search + filters + pagination) |
| `GET` | `/api/v1/games/{id}` | Get game detail |
| `DELETE` | `/api/v1/games/{id}` | Delete game |
| `POST` | `/api/v1/games/{id}/collections` | Set game collections |
| `POST` | `/api/v1/games/bulk-collections` | Bulk assign collections |
| `PUT` | `/api/v1/games/{id}/rules-url` | Update rules URL (Google Drive only) |
| `POST` | `/api/v1/games/{id}/player-aids` | Upload player aid image |
| `DELETE` | `/api/v1/games/{id}/player-aids/{aid_id}` | Delete player aid |
| `GET` | `/api/v1/collections` | List collections |
| `POST` | `/api/v1/collections` | Create collection |
| `PUT` | `/api/v1/collections/{id}` | Update collection |
| `DELETE` | `/api/v1/collections/{id}` | Delete collection |
| `GET` | `/api/v1/discover` | Filter games within a collection |

## Architecture

```
cmd/server/main.go
internal/
  config/config.go
  handler/handler.go    ← all routes registered here
  service/service.go    ← business logic
  store/store.go        ← SQL + file I/O
  model/model.go        ← Game, Collection, PlayerAid, GameFilter
migrations/
  001_init.up.sql       ← games schema (Postgres FTS via tsvector)
deploy/
  Dockerfile
  fly.toml              ← mounts persistent volume for uploads
```

## Key design notes

- `search_vector` is a **generated column** — automatically kept in sync with name/description, no triggers needed
- `user_id` is a UUID (Supabase Auth); every query filters by it for multi-tenancy
- The `vibes` JSON key is kept for React app backward compatibility (maps to `collections` internally)
- Player aid files are stored on a Fly.io persistent volume mounted at `/data`

## Environment variables

| Var | Required | Default |
|-----|----------|---------|
| `DATABASE_URL` | yes | — |
| `PORT` | no | `8002` |
| `DATA_DIR` | no | `data` |
