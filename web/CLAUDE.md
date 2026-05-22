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
npm install
npm run dev      # local dev server
npm run build    # production build → dist/
npm run lint
npm run test
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
- All API calls go through a central `api/` module that attaches the JWT header
- TypeScript strict mode — no `any`


<claude-mem-context>
</claude-mem-context>
