# E2E tests

Playwright UI test suite for the React app. Self-contained under `e2e/` so it
can later be extracted into its own package or service without touching the
app code.

## Layout

```
e2e/
├── fixtures/           # Playwright fixtures (shared setup)
│   └── auth.ts         # `authenticatedPage` fixture + seedAuth()
├── helpers/            # Small, dependency-free utilities
│   ├── nav.ts          # goToCollection / goToFirstGame / goToVibes
│   └── mocks.ts        # mockLogin — intercepts /auth/login
├── tests/              # Spec files, one per feature area
│   ├── auth.spec.ts
│   ├── collection.spec.ts
│   ├── game-detail.spec.ts
│   ├── lightbox.spec.ts
│   ├── navigation.spec.ts
│   └── vibes.spec.ts
└── README.md
```

Playwright is configured to discover tests in `e2e/tests` only
(see `playwright.config.ts`). Anything outside that folder is support code.

## Running

```sh
# Unauthenticated / mocked tests only (no backend needed)
bun run test:e2e --grep "@mocked|Auth"

# Full suite (needs backend + ephemeral token)
TEST_TOKEN=<ephemeral-jwt> bun run test:e2e

# Single file
bun run test:e2e e2e/tests/collection.spec.ts

# Headed / debug
bun run test:e2e --headed
bun run test:e2e --debug
```

The Vite dev server is started automatically by Playwright
(`webServer.command = "bun dev"`).

## Authentication protocol

Tests must never use static usernames or passwords. Two paths are allowed:

1. **Primary — mock.** Intercept `/api/v1/auth/login` via `mockLogin(page)`
   (`helpers/mocks.ts`). Use this for anything that exercises the login UI.
2. **Fallback — ephemeral JWT.** When a real session is required (most
   authenticated flows), set `TEST_TOKEN` to an ephemeral JWT. The
   `authenticatedPage` fixture seeds it into `localStorage`. Optionally set
   `TEST_REFRESH_TOKEN`; if omitted the access token is reused.
3. **No viable path → halt.** If neither mock nor token is available the
   suite throws a blocker. Do not invent credentials.

The token is never logged, printed, or echoed. Do not add `console.log`
statements that touch `TEST_TOKEN` or the `access_token` returned by the API.

## Writing a test

**Authenticated (default for UI flows):**

```ts
import { test, expect } from '../fixtures/auth'
import { goToFirstGame } from '../helpers/nav'

test('game detail shows BGG link', async ({ authenticatedPage: page }) => {
  await goToFirstGame(page)
  await expect(page.getByRole('link', { name: /boardgamegeek/i })).toBeVisible()
})
```

**Unauthenticated (login UI, redirects):**

```ts
import { test, expect } from '@playwright/test'
import { mockLogin } from '../helpers/mocks'

test('login success', async ({ page }) => {
  await mockLogin(page)
  // ...
})
```

## Conventions

- **One file per feature area.** Match the page or domain (`collection`,
  `game-detail`, `vibes`). Keep each file short.
- **No hardcoded credentials, URLs, or user IDs.** Use fixtures, env vars,
  or data queried from the UI.
- **Prefer role/label selectors** (`getByRole`, `getByLabel`) over
  CSS/XPath. They double as accessibility checks.
- **Small, composable helpers.** If a helper grows past ~15 lines, split it.
- **No cross-file imports between spec files.** Specs depend only on
  `fixtures/` and `helpers/`.
- **Skip gracefully** when a precondition is missing (e.g. no player aids
  uploaded) rather than asserting false positives.

## Migration path: extracting to its own service

The folder is intentionally self-contained. To lift it into a standalone
testing service:

1. `git mv react-app/e2e tests-service/`
2. Create `tests-service/package.json` with `@playwright/test` as a dep.
3. Copy `react-app/playwright.config.ts` over and point `webServer.command`
   at whatever launches the app under test (Docker, a deployed URL, etc.).
4. Update `baseURL` to an env var so the same suite runs against local,
   staging, and production.

Nothing in `fixtures/`, `helpers/`, or `tests/` imports from the React app
source, so the move is mechanical.
