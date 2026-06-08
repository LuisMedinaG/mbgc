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
│   └── nav.ts           # goToCollection / goToFirstGame / goToVibes
├── tests/               # Spec files, one per feature area
│   ├── auth.spec.ts
│   ├── collection.spec.ts
│   ├── game-detail.spec.ts
│   ├── import.spec.ts
│   ├── navigation.spec.ts
│   ├── profile.spec.ts
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
bunx playwright test e2e/tests/vibes.spec.ts

# With a real backend (live mode)
TEST_TOKEN=<supabase-jwt> bun run test:e2e
```

## Mock strategy

By default (no `TEST_TOKEN`), `fixtures/auth.ts` calls `mockAll()` from
`helpers/api-mocks.ts`, which intercepts every `/api/v1/*` request. Fixture
data (games, collections, profile) lives in that file — update it once to
change what all tests see.

The mocks hold state in module-local `state` arrays (collections, games)
so a single test can assert CRUD round-trips without re-mounting the app.
Call `resetState()` in `beforeEach` to restore defaults.

## Coverage philosophy

These tests are **broad, not deep**. They verify the major user flows
work end-to-end (UI → API contract → backend response shape), but they
do NOT check CSS, copy text, or visual details. The goal is to catch:

- Broken API contracts (frontend calls an endpoint wrong way)
- Unimplemented stub handlers (returns 404 / NOT_FOUND silently)
- Error display bugs (`[object Object]` instead of real message)
- Missing UI affordances for happy-path flows
- Auth/redirect logic failures

The earlier suite missed all of these. The new suite asserts on
**observable behavior** — what the user sees and what the API receives.

## Per-spec coverage

| Spec | Covers |
|---|---|
| `auth.spec` | Login success/failure, 401 → token refresh, unauthenticated redirect |
| `collection.spec` | List renders, search filter narrows, nav to detail, empty state |
| `game-detail.spec` | Render + stats, BGG link, vibe edit/cancel, rules URL validation, delete confirm |
| `vibes.spec` | Create/rename/delete CRUD, discover (browse games in a collection) |
| `import.spec` | BGG sync (gated by username), full refresh, success/fail, CSV upload → preview → import |
| `profile.spec` | View + change BGG username, success/error feedback |
| `navigation.spec` | Tab navigation between pages |

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
- **Test the API call shape, not just the UI.** Use `page.waitForRequest` to assert
  the request body/method/URL — that's where contract bugs hide.
- **Always assert error messages are shown, not `[object Object]`.** This was the
  bug class that bit us last time — make it impossible to regress.
- **Reset shared state between tests.** Call `resetState()` in `beforeEach` if
  your spec mutates collections or games.

## Debugging

- `[WebServer] ...` lines in test output are from Vite's stdout (warnings, errors).
- For detailed request/response logs, add `page.on('request', ...)` /
  `page.on('response', ...)` to your test.
- `test-results/<spec>-<test>/` contains screenshots + videos for failed runs.
- For backend failures, check the API log at `/tmp/api.log` (if running via `make dev`).
