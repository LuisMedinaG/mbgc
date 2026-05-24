# AGENTS.md — web

React 19 + TypeScript strict + Tailwind v4 + Vite. Deployed to Cloudflare Pages.

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
- On 401 → `api.ts` auto-refreshes via `/auth/refresh`; on refresh failure → `onAuthFailure` callback fires → logout
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
