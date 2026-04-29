# mbgc — Ecosystem Context

Personal board game collection app. Originally a Go monolith (`myboardgamecollection`),
being decomposed into focused microservices. Both coexist during migration.

## Services

| Repo | Lang | Role | Deploy |
|---|---|---|---|
| `myboardgamecollection` | Go | Monolith (HTMX + REST API) — full feature set | Fly.io |
| `mbgc-gateway` | Go | API gateway — JWT validation, routing, CORS | Fly.io |
| `mbgc-auth-service` | Go | Profile service — BGG username, quotas, admin roles (Supabase auth) | Fly.io |
| `mbgc-game-service` | Go | Core domain — games, collections, player aids, file uploads | Fly.io |
| `mbgc-importer-service` | Go | BGG sync + CSV import | Fly.io |
| `mbgc-web` | TypeScript | React frontend | Cloudflare Pages |
| `mbgc-shared` | Go | Shared module — response envelope, error codes, HTTP middleware | (library) |
| `mbgc-infra` | HCL | Terraform IaC — Fly, Cloudflare, Supabase | — |
      
## Request Flow

```
Browser / mbgc-web
      │
      ▼
mbgc-gateway  (validates JWT, routes by path prefix)
      ├──▶ mbgc-auth-service     /auth/*  /profile/*
      ├──▶ mbgc-game-service     /games/* /collections/* /player-aids/*
      └──▶ mbgc-importer-service /import/*
```

The monolith (`myboardgamecollection`) runs independently and is not behind the gateway.

## Shared Conventions

- **Language:** Go 1.25 (services) · TypeScript / React (web)
- **Auth:** JWT — access tokens (15 min), refresh tokens (30 day)
- **Response envelope:** `{ "data": ... }` success · `{ "error": "..." }` failure
- **Pagination:** top-level `total`, `page`, `per_page` on list responses
- **Errors:** sentinel errors in `mbgc-shared` — never leak raw DB errors to clients
- **DB:** SQLite (`modernc.org/sqlite`) in monolith; services may use Postgres via Supabase

## Branching Strategy (all repos)

```
feature/*  →  dev  →  staging  →  main
```

Promotion: `dev → staging` and `staging → main` require PRs.
Direct push to `main`/`staging` is blocked (admin bypass exists for emergencies).

## Infrastructure

- **Fly.io** — all Go services (persistent volume at `/data` for monolith)
- **Cloudflare Pages** — `mbgc-web` frontend
- **Supabase** — auth provider for microservices
- **Terraform** — `mbgc-infra` is the single source of truth for all cloud resources

<claude-mem-context>
</claude-mem-context>
