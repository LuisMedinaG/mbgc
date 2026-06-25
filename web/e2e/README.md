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

## Prerequisites

```sh
bun install
bunx playwright install chromium   # desktop browser
bunx playwright install webkit      # iOS viewport emulation (macOS only)
```

> **Note for macOS users:** WebKit (required for iOS viewport tests) only runs on macOS.
> On Linux you can only run the `chromium` project.

**Don't run this while a stray Vite dev server is squatting on `:5173` from
an unrelated tool** — `reuseExistingServer: false` in `playwright.config.ts`
prevents Playwright from attaching to one accidentally, but if port `:5173`
itself is occupied by something else, the webServer launch will fail. Free
the port (`lsof -i :5173`) and rerun.

## Running

```sh
# Full suite (chromium only) — mocked mode, no backend needed
bun run test:e2e

# Full suite including iOS viewport — requires macOS (WebKit only runs on macOS)
bun run test:e2e --project=chromium --project=iOS

# iOS viewport only — requires macOS
bunx playwright test --project=iOS

# Interactive UI mode
bunx playwright test --ui

# Single file
bunx playwright test e2e/tests/vibes.spec.ts

# Single file on iOS viewport
bunx playwright test e2e/tests/vibes.spec.ts --project=iOS

# With a real backend (live mode)
TEST_TOKEN=<jwt> bun run test:e2e
```

### Getting a TEST_TOKEN (live mode)

Live mode skips all mocking and drives your real local API + Postgres. You
need a valid access token from a logged-in user. The API issues these on
login — the same token you'd see in the browser's localStorage after
signing in.

1. Make sure the API is running locally (`make dev` from repo root, or
   `make dev` inside `services/api`) and you have an admin user seeded
   (`SEED_ADMIN_EMAIL` / `SEED_ADMIN_PASSWORD` in `services/api/.env` —
   see `AGENTS.md` → "Admin user").
2. Log in via the API to get a token:

   ```sh
   curl -s -X POST http://localhost:8080/api/v1/auth/login \
     -H "Content-Type: application/json" \
     -d '{"username":"<SEED_ADMIN_EMAIL>","password":"<SEED_ADMIN_PASSWORD>"}' \
     | jq -r '.data.access_token'
   ```

3. Export it and run the suite:

   ```sh
   TEST_TOKEN=<token from step 2> bun run test:e2e
   ```

Access tokens expire in 15 minutes — re-run step 2 if your test run takes
longer than that or fails with 401s partway through. `TEST_REFRESH_TOKEN`
is optional; if unset, `TEST_TOKEN` is reused as the refresh token too
(fine for short local runs, but it won't actually refresh anything since
it's not a real refresh token — get a fresh `TEST_TOKEN` instead of relying
on auto-refresh in live mode).

Never commit a token or put it in a file tracked by git — pass it inline
on the command line or via your shell's untracked `.env.local`-style file.

## Mock strategy

By default (no `TEST_TOKEN`), `fixtures/auth.ts` calls `mockAll()` from
`helpers/api-mocks.ts`, which intercepts every `/api/v1/*` request. Fixture
data (games, collections, profile) lives in that file — update it once to
change what all tests see.

The mocks hold state in module-local `state` arrays (collections, games)
so a single test can assert CRUD round-trips without re-mounting the app.
Call `resetState()` in `beforeEach` to restore defaults.

### Per-test overrides

`mockAll(page, overrides?)` accepts a typed overrides object that tweaks
a single endpoint's response. Pass overrides instead of calling
`page.route()` yourself — Playwright runs route handlers most-recently-registered-first,
so a second handler for the same URL can silently shadow the one `mockAll`
already installed. The available keys:

```ts
await mockAll(page, {
  profile:     { bggUsername: 'mybgg', isAdmin: true },  // /api/v1/profile
  games:       { empty: true },                          // /api/v1/games
  collections: { empty: true },                          // /api/v1/collections
  bggSync:     { body: { imported: 5, skipped: 2, failed: 1 } },
  csvImport:   { previewStatus: 400, previewError: 'CSV must have an objectid column' },
  auth:        { loginStatus: 401, loginError: 'invalid' },
})
```

Any field left out falls back to the default fixture. Use this for every
test that needs anything other than the happy path with the default user.

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
| `collection.spec` | List renders, search filter narrows, category filter narrows, filter chip remove, nav to detail, empty state |
| `game-detail.spec` | Render + stats, BGG link, vibe edit/cancel, rules URL validation, delete confirm |
| `vibes.spec` | Create/rename/delete CRUD, discover (browse games in a collection) |
| `import.spec` | BGG sync (gated by username), full refresh, success/fail, CSV upload → preview → import |
| `profile.spec` | View + change BGG username, success/error feedback |
| `navigation.spec` | Tab navigation between pages |

## CI

`.github/workflows/e2e.yml` runs two parallel jobs:

| Job | Runner | Browser | What it tests |
|---|---|---|---|
| `e2e-desktop` | ubuntu-24.04 | Chromium | Full desktop viewport (1280×720) |
| `e2e-ios` | macos-14 | WebKit (iPhone 17 Pro) | iOS viewport (390×844) + touch + Mobile Safari UA |

Both jobs run on every PR. On `workflow_dispatch` you can choose: `all`
(both), `chromium` (desktop only), or `webkit` (iOS only).

On failure the Playwright report is uploaded as `playwright-report-<desktop|ios>`
(7-day retention).

### Adding `TEST_TOKEN` for live-mode CI runs

1. Get a token as described in [Getting a TEST_TOKEN](#getting-a-test_token-live-mode) above.
2. Add it as a repo secret: **Settings → Secrets and variables → Actions →
   New repository secret**, name `TEST_TOKEN`
   (or `gh secret set TEST_TOKEN --repo lumedinda/mbgc`).
3. Already wired up — `.github/workflows/e2e.yml` passes `TEST_TOKEN: ${{ secrets.TEST_TOKEN }}`
   to the test step unconditionally. No `if:` guard needed: when the secret
   isn't set, GitHub Actions resolves it to an empty string, and `seedAuth`
   (`fixtures/auth.ts`) treats an empty `TEST_TOKEN` the same as unset —
   falling back to mocked mode.

Since CI tokens expire in 15 minutes (see above), live mode only works for
short-lived manual (`workflow_dispatch`) runs against a live `base_url` —
not for the PR-triggered run, where the token would likely be stale by the
time the job starts.

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
