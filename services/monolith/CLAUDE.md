# services/monolith [DEPRECATED]

⚠️ **This service is being decommissioned.** It is the original Go monolith that is
being replaced by the microservices in `services/`. All new development should
target the microservices.

## Status

- **Production:** Still running on Fly.io
- **Migration:** In progress — features being ported to microservices
- **Replacement:** `services/gateway` + `services/auth` + `services/game` + `services/importer`

## What's being migrated

| Feature | Monolith location | Microservice target |
|---|---|---|
| Auth (login/refresh/logout) | `services/auth/` | `services/auth/` |
| Profile | `services/profile/` | `services/auth/` |
| Games CRUD | `services/games/` | `services/game/` |
| Collections | `services/collections/` | `services/game/` |
| BGG Import | `services/importer/` | `services/importer/` |
| File uploads | `services/files/` | `services/game/` |

## DB

SQLite (`modernc.org/sqlite`) — single file at `/data/games.db`.
Migrations are additive (`ALTER TABLE`) and idempotent.

## Commands

```sh
make dev      # go run .
make build    # outputs ./server binary
make test     # all Go tests
make cover    # coverage report
```

## Deployment

Fly.io — `fly.toml` at repo root.
Persistent volume `boardgame_data` mounted at `/data`.

<claude-mem-context>
</claude-mem-context>
