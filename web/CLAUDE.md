# mbgc-web

React frontend for mbgc — replaces the Go/HTMX templates from the monolith.
Deployed to Cloudflare Pages; talks exclusively to mbgc-gateway.

## Stack

- **Language:** TypeScript
- **Framework:** React
- **Deploy:** Cloudflare Pages
- **API:** mbgc-gateway (JWT in `Authorization: Bearer`)

## Auth flow

1. User logs in → mbgc-auth-service returns access + refresh tokens
2. Access token (15 min) stored in memory; refresh token in `httpOnly` cookie
3. On 401 → auto-refresh via `/auth/refresh`; on refresh failure → logout

## Commands

```sh
make install  # bun install
make dev      # Vite dev server
make build    # tsc -b && vite build → dist/
make lint     # eslint
make test-e2e # Playwright e2e (requires full backend stack)
```

## Environment variables

| Var | Purpose |
|---|---|
| `VITE_API_BASE_URL` | mbgc-gateway base URL |

## Deployment

Push to `main` triggers Cloudflare Pages deploy automatically.
Preview deploys on every PR (Cloudflare integration).

## Key conventions

- No JS framework beyond React — keep it lean
- All API calls go through `src/lib/api.ts` — never raw `fetch()` in components or hooks
- Access token stored in memory; refresh token in `httpOnly` cookie — never localStorage
- TypeScript strict mode — no `any`
- No unit test framework — only Playwright e2e in `e2e/`


<claude-mem-context>
</claude-mem-context>
