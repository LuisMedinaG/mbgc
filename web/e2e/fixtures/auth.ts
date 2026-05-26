import { test as base, type Page } from '@playwright/test'
import { mockAll } from '../helpers/api-mocks'

/**
 * Authentication strategy for the E2E suite.
 *
 * Mocked mode (default, used in CI):
 *   All API routes are intercepted by `mockAll`. The fixture seeds
 *   localStorage with fake tokens so the app boots authenticated.
 *   No backend required.
 *
 * Live mode (optional, local dev):
 *   Set TEST_TOKEN=<supabase-jwt> to skip mocking and hit a real backend.
 *   The token is seeded into localStorage directly — never logged or committed.
 */
const MOCK_ACCESS  = 'mock.jwt.access'
const MOCK_REFRESH = 'mock.jwt.refresh'

export async function seedAuth(page: Page): Promise<void> {
  const liveToken = process.env.TEST_TOKEN

  if (!liveToken) {
    // Mocked mode — intercept all API calls, seed fake tokens
    await mockAll(page)
    await page.goto('/')
    await page.evaluate(({ a, r }) => {
      localStorage.setItem('mbgc_access', a)
      localStorage.setItem('mbgc_refresh', r)
    }, { a: MOCK_ACCESS, r: MOCK_REFRESH })
    return
  }

  // Live mode — real token provided; skip API mocking
  const refreshToken = process.env.TEST_REFRESH_TOKEN ?? liveToken
  await page.goto('/')
  await page.evaluate(({ a, r }) => {
    localStorage.setItem('mbgc_access', a)
    localStorage.setItem('mbgc_refresh', r)
  }, { a: liveToken, r: refreshToken })
}

type AuthFixtures = {
  authenticatedPage: Page
}

/**
 * Extended test runner with pre-seeded authentication.
 *
 *   import { test, expect } from '../fixtures/auth'
 *   test('...', async ({ authenticatedPage }) => { ... })
 *
 * For unauthenticated / login-UI tests, use the plain `page` fixture from
 * `@playwright/test` directly.
 */
export const test = base.extend<AuthFixtures>({
  authenticatedPage: async ({ page }, use) => {
    await seedAuth(page)
    await use(page)
  },
})

export { expect } from '@playwright/test'
