# mbgc-gateway

Public API gateway for all mbgc microservices. The only service exposed to the internet.

## Responsibilities

- Validates Supabase JWTs on every protected request
- Injects `X-User-ID`, `X-Username`, `X-Is-Admin` headers for internal services
- Reverse-proxies requests to the correct internal service
- CORS, security headers, request logging, panic recovery

## Route map

| Path prefix | Service | Auth |
|-------------|---------|------|
| `/api/v1/auth/*` | mbgc-auth-service | public |
| `/api/v1/games/*` | mbgc-game-service | required |
| `/api/v1/collections/*` | mbgc-game-service | required |
| `/api/v1/discover` | mbgc-game-service | required |
| `/api/v1/profile/*` | mbgc-auth-service | required |
| `/api/v1/import/*` | mbgc-importer-service | required |
| `/healthz` | gateway | public |

## Environment variables

| Var | Required | Default | Description |
|-----|----------|---------|-------------|
| `SUPABASE_JWT_SECRET` | yes | — | From Supabase Settings > API > JWT Secret |
| `PORT` | no | `8000` | Listen port |
| `AUTH_SERVICE_URL` | no | `http://localhost:8001` | Internal auth-service URL |
| `GAME_SERVICE_URL` | no | `http://localhost:8002` | Internal game-service URL |
| `IMPORTER_SERVICE_URL` | no | `http://localhost:8003` | Internal importer-service URL |
| `ALLOWED_ORIGIN` | no | `http://localhost:5173` | CORS allowed origin |

## Local development

```sh
cp .env.example .env  # fill in SUPABASE_JWT_SECRET
make dev
```

For local dev with sibling repos, add to `go.mod`:
```
replace github.com/LuisMedinaG/mbgc-shared => ../mbgc-shared
```

## Fly.io deployment

```sh
fly secrets set SUPABASE_JWT_SECRET=<value>
fly secrets set AUTH_SERVICE_URL=http://mbgc-auth-service.internal:8001
fly secrets set GAME_SERVICE_URL=http://mbgc-game-service.internal:8002
fly secrets set IMPORTER_SERVICE_URL=http://mbgc-importer-service.internal:8003
fly deploy
```
