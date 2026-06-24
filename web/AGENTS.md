# AGENTS.md — web

React 19 + TypeScript strict + Tailwind v4 + Vite. Deployed to Cloudflare Pages; talks exclusively to `services/api` (`mbgc-api` on GCP, `api.lumedina.dev` in prod).

## Stack

- **Language:** TypeScript (strict mode — no `any`)
- **Framework:** React 19 + react-router-dom + TanStack Query v5 + Tailwind v4 (CSS-first, no `tailwind.config.js`)
- **Build:** Vite + `@tailwindcss/vite`
- **Deploy:** Cloudflare Pages — push to `main` auto-deploys; every PR gets a preview deploy
- **Env var:** `VITE_API_BASE_URL` — API base URL (empty in dev — Vite proxies `/api/*` to `:8080`)

## Auth flow

1. User logs in through `services/api`, which proxies Supabase Auth.
2. Access token (15 min) is stored in memory only; refresh token is set by the API as an `HttpOnly` cookie.
3. On 401 → `api.ts` calls the refresh endpoint with `credentials: 'include'`; on failure → `onAuthFailure` callback fires → logout

## Commands

```sh
bun install
bun run dev          # Vite dev server
bun run build        # tsc -b && vite build → dist/
bun run lint         # eslint
bun run test:e2e     # Playwright — mocked, no backend needed (see web/e2e/README.md)
```

## Patterns

- All API calls through `src/lib/api.ts` — never raw `fetch()` in components or hooks; all methods are typed
- **Server state via TanStack Query** — all data fetching uses `useQuery`/`useMutation` from `@tanstack/react-query`. Query keys are in `src/lib/queryKeys.ts`; client config in `src/lib/queryClient.ts` (30s staleTime, 1 retry, no refetch-on-focus)
- Hook conventions: `useGames(filters)` for the collection list (debounces search via `useDebounce`), `useGame(id)` for detail page, `useCollections()` for CRUD, `useProfile()` for profile + mutations, `useImport()` / `useCsvImport()` for import flows, `useDiscover(collectionId)` for vibe discovery, and focused hooks like `useRulesUrl(gameId)` / `usePlayerAids(gameId, initial)` for detail subfeatures. Never reach into the query cache from components — use the hooks.
- Auth: access token stored in memory; refresh token stored only in an HttpOnly cookie set by the API
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
