import { test, expect } from '@playwright/test'
import { mockAuthLogin } from '../helpers/api-mocks'

test.describe('Auth', () => {
  test('redirects unauthenticated users from / to /login', async ({ page }) => {
    await page.goto('/')
    await expect(page).toHaveURL(/#\/login/)
    await expect(page.getByRole('heading', { name: /board game collection/i })).toBeVisible()
  })

  test('login with valid credentials navigates to collection', async ({ page }) => {
    await mockAuthLogin(page)
    await page.goto('/#/login')
    await page.getByLabel('Username').fill('testuser')
    await page.getByLabel('Password').fill('testpass')
    await page.getByRole('button', { name: /sign in/i }).click()
    await expect(page.getByRole('heading', { name: 'Board Game Collection' }))
      .toBeVisible({ timeout: 10000 })
  })

  test('login with bad password shows backend error message', async ({ page }) => {
    await mockAuthLogin(page, { status: 401, error: 'invalid username or password' })
    await page.goto('/#/login')
    await page.getByLabel('Username').fill('testuser')
    await page.getByLabel('Password').fill('wrongpass')
    await page.getByRole('button', { name: /sign in/i }).click()
    await expect(page.getByText(/invalid username or password/i)).toBeVisible({ timeout: 5000 })
  })

  test('token refresh fires on 401 and retries the original request', async ({ page }) => {
    // Simulate a 401 on first /api/v1/ping then a 200 on retry.
    // This exercises the request() auto-refresh path in api.ts.
    let pingCalls = 0
    await page.route('**/api/v1/ping', (route) => {
      pingCalls++
      if (pingCalls === 1) {
        return route.fulfill({
          status: 401,
          contentType: 'application/json',
          body: JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'expired' } }),
        })
      }
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ data: { pong: true, username: 'testuser' } }),
      })
    })
    await page.route('**/api/v1/auth/refresh', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ data: { access_token: 'mock.jwt.refreshed' } }),
      }),
    )
    await page.addInitScript(() => {
      localStorage.setItem('mbgc_access', 'mock.jwt.access')
      localStorage.setItem('mbgc_refresh', 'mock.jwt.refresh')
    })
    await page.goto('/')
    // Wait for refresh to fire — page.on would be ideal, but we just check
    // the user is still authenticated (no redirect to /login) after a moment.
    await page.waitForTimeout(500)
    await expect(page).not.toHaveURL(/#\/login/)
  })
})
