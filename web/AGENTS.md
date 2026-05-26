# AGENTS.md — web

React 19 + TypeScript strict + Tailwind v4 + Vite. Deployed to Cloudflare Pages; talks exclusively to `services/api` (`mbgc-api` on GCP, `api.lumedina.dev` in prod).

## Stack

- **Language:** TypeScript (strict mode — no `any`)
- **Framework:** React 19 + react-router-dom + Tailwind v4 (CSS-first, no `tailwind.config.js`)
- **Build:** Vite + `@tailwindcss/vite`
- **Deploy:** Cloudflare Pages — push to `main` auto-deploys; every PR gets a preview deploy
- **Env var:** `VITE_API_BASE_URL` — API base URL (empty in dev — Vite proxies `/api/*` to `:8080`)

## Auth flow

1. User logs in via Supabase Auth SDK → receives access + refresh tokens
2. Access token (15 min) stored in memory; refresh token in `httpOnly` cookie
3. On 401 → `api.ts` auto-refreshes via Supabase refresh endpoint; on failure → `onAuthFailure` callback fires → logout

## Commands

```sh
bun install
bun run dev          # Vite dev server
bun run build        # tsc -b && vite build → dist/
bun run lint         # eslint
bun run test:e2e     # Playwright — requires full backend stack running
```

## Patterns

- All API calls through `src/lib/api.ts` — never raw `fetch()` in components or hooks; all methods are typed
- Auth: access token stored in memory (not localStorage); refresh token in `httpOnly` cookie
- Tailwind v4 CSS-first config (no `tailwind.config.js`) — custom design tokens in `src/index.css`
- Routing via react-router-dom — never `window.location` redirects

## Boundaries

**Never:**
- Store access or refresh tokens in `localStorage` or `sessionStorage`
- Use `any` — TypeScript strict mode is enforced
- Make direct `fetch()` calls outside `src/lib/api.ts`

**Ask first:**
- Adding a new npm/bun dependency
- Changes to auth token storage or refresh flow (security-sensitive)
