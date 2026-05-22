import { test as base, type Page } from '@playwright/test'

/**
 * Authentication protocol for the E2E suite.
 *
 * 1. Primary — mock `/api/v1/auth/login` via `page.route()` in the test itself
 *    (see `helpers/mocks.ts`). Use this for anything that exercises the login
 *    UI or does not require a real authenticated session.
 * 2. Fallback — for flows that must hit the real backend, use TEST_TOKEN if
 *    provided, otherwise auto-login with TEST_USER/TEST_PASSWORD (defaults to
 *    testuser/testpass123). The fixture seeds localStorage so the app boots
 *    authenticated.
 * 3. If auto-login fails and no TEST_TOKEN is provided, tests halt with a blocker.
 *
 * Static usernames/passwords are never allowed in TEST_TOKEN. The token is never logged.
 */
function readEphemeralToken(): { access: string; refresh: string } {
  const access = process.env.TEST_TOKEN
  if (access) {
    return { access, refresh: process.env.TEST_REFRESH_TOKEN ?? access }
  }

  // If no TEST_TOKEN provided, try to login automatically
  return { access: '', refresh: '' } // Will be filled by seedAuth
}

export async function seedAuth(page: Page): Promise<void> {
  let { access, refresh } = readEphemeralToken()

  if (!access) {
    // Auto-login with test credentials
    const testUser = process.env.TEST_USER || 'testuser'
    const testPass = process.env.TEST_PASSWORD || 'testpass123'

    const response = await page.request.post('/api/v1/auth/login', {
      data: { username: testUser, password: testPass }
    })

    if (!response.ok()) {
      throw new Error(`Auto-login failed: ${response.status()} ${response.statusText()}`)
    }

    const data = await response.json()
    access = data.data.access_token
    refresh = data.data.refresh_token
  }

  await page.goto('/')
  await page.evaluate(({ a, r }) => {
    localStorage.setItem('mbgc_access', a)
    localStorage.setItem('mbgc_refresh', r)
  }, { a: access, r: refresh })
}

type AuthFixtures = {
  authenticatedPage: Page
}

/**
 * Extended test runner. Use `test` from this module instead of `@playwright/test`
 * when a test needs to start already authenticated:
 *
 *   test('...', async ({ authenticatedPage }) => { ... })
 *
 * For unauthenticated / login-UI tests, use the plain `page` fixture.
 */
export const test = base.extend<AuthFixtures>({
  authenticatedPage: async ({ page }, use) => {
    await seedAuth(page)
    await use(page)
  },
})

export { expect } from '@playwright/test'
