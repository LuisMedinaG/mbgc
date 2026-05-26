# E2E tests

Playwright UI test suite for the React app. Runs in CI without a backend — all
API routes are intercepted at the network level by mock handlers in `helpers/api-mocks.ts`.

## Layout

```
e2e/
├── fixtures/
│   └── auth.ts          # authenticatedPage fixture — mocked by default, live with TEST_TOKEN
├── helpers/
│   ├── api-mocks.ts     # Mock handlers for all /api/v1/* routes + fixture data
│   ├── nav.ts           # goToCollection / goToFirstGame / goToVibes
│   └── mocks.ts         # deprecated re-export — use api-mocks.ts directly
├── tests/               # Spec files, one per feature area
│   ├── auth.spec.ts
│   ├── collection.spec.ts
│   ├── game-detail.spec.ts
│   ├── lightbox.spec.ts
│   ├── navigation.spec.ts
│   └── vibes.spec.ts
└── README.md
```

## Running

```sh
# Full suite — mocked mode, no backend needed (what CI runs)
bun run test:e2e

# Interactive UI mode
bunx playwright test --ui

# Single file
bun run test:e2e e2e/tests/auth.spec.ts

# With a real backend (live mode)
TEST_TOKEN=<supabase-jwt> bun run test:e2e
```

## Mock strategy

By default (no `TEST_TOKEN`), `fixtures/auth.ts` calls `mockAll()` from
`helpers/api-mocks.ts`, which intercepts every `/api/v1/*` request. Fixture
data (games, collections, profile) lives in that file — update it once to
change what all tests see.

To override a single route inside a test:

```ts
import { mockAll, FIXTURE_GAMES } from '../helpers/api-mocks'

test.beforeEach(async ({ page }) => await mockAll(page))

test('shows empty state', async ({ page }) => {
  // Re-register the route to override — last registration wins
  await page.route('**/api/v1/games*', route =>
    route.fulfill({ status: 200, contentType: 'application/json',
      body: JSON.stringify({ data: [], meta: { page: 1, limit: 20, total: 0 } }) }),
  )
  // ...
})
```

## Writing a test

**Authenticated (default for UI flows):**

```ts
import { test, expect } from '../fixtures/auth'
import { goToFirstGame } from '../helpers/nav'

test('game detail shows name', async ({ authenticatedPage: page }) => {
  await goToFirstGame(page)
  await expect(page.locator('h1').first()).toBeVisible()
})
```

**Unauthenticated (login UI, redirects):**

```ts
import { test, expect } from '@playwright/test'
import { mockAuthLogin } from '../helpers/api-mocks'

test('login form submits', async ({ page }) => {
  await mockAuthLogin(page)
  // ...
})
```

## CI

The `e2e` job in `.github/workflows/ci.yml` runs the full suite in mocked mode.
On failure the Playwright report is uploaded as `playwright-report` (7-day retention).

To run with a real Supabase token in CI, add `TEST_TOKEN` as a GitHub Actions
secret and pass it via `env:` in the workflow step.

## Conventions

- **One file per feature area.** Match the page or domain (`collection`, `game-detail`, `vibes`).
- **No hardcoded credentials, URLs, or user IDs.** Use `FIXTURE_*` constants from `api-mocks.ts`.
- **Prefer role/label selectors** (`getByRole`, `getByLabel`) over CSS/XPath.
- **No cross-file imports between spec files.** Specs depend only on `fixtures/` and `helpers/`.
- **Skip gracefully** when a precondition is missing rather than asserting false positives.
