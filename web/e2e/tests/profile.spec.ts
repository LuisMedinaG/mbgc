import { test, expect } from '../fixtures/auth'
import { resetState } from '../helpers/api-mocks'

test.describe('Profile page', () => {
  test.beforeEach(() => { resetState() })

  test('shows username and bgg_username from API', async ({ authenticatedPage: page }) => {
    await page.goto('/#/profile')
    await expect(page.getByRole('heading', { name: 'Profile' })).toBeVisible({ timeout: 8000 })
    await expect(page.getByText('testuser').first()).toBeVisible()
  })

  test('saving a new BGG username sends PUT and shows success', async ({ authenticatedPage: page }) => {
    const putPromise = page.waitForRequest('**/api/v1/profile/bgg-username')
    await page.goto('/#/profile')
    await expect(page.getByRole('heading', { name: 'Profile' })).toBeVisible({ timeout: 8000 })
    await page.getByLabel(/bgg username/i).fill('newBggUser')
    await page.getByRole('button', { name: 'Save' }).click()
    const req = await putPromise
    expect(req.method()).toBe('PUT')
    expect(JSON.parse(req.postData() ?? '{}').bgg_username).toBe('newBggUser')
    await expect(page.getByText('Saved').first()).toBeVisible({ timeout: 5000 })
  })

  test('failed save shows backend error, not [object Object]', async ({ page }) => {
    resetState()
    await page.route('**/api/v1/ping', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { pong: true, username: 't' } }) }))
    await page.route('**/api/v1/profile', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { id: 'u1', username: 't', bgg_username: 't', is_admin: false } }) }))
    await page.route('**/api/v1/games*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 20, total: 0 } }) }))
    await page.route('**/api/v1/collections*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 0, total: 0 } }) }))
    await page.route('**/api/v1/auth/refresh', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { access_token: 'mock.jwt.refreshed' } }) }))
    await page.route('**/api/v1/profile/bgg-username', (route) =>
      route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: { code: 'INTERNAL_ERROR', message: 'database unavailable' } }),
      }),
    )
    await page.addInitScript(() => {
      localStorage.setItem('mbgc_access', 'mock.jwt.access')
      localStorage.setItem('mbgc_refresh', 'mock.jwt.refresh')
    })
    await page.goto('/#/profile')
    await expect(page.getByRole('heading', { name: 'Profile' })).toBeVisible({ timeout: 8000 })
    await page.getByLabel(/bgg username/i).fill('something')
    await page.getByRole('button', { name: 'Save' }).click()
    await expect(page.getByText('database unavailable')).toBeVisible({ timeout: 5000 })
    await expect(page.getByText('[object Object]')).not.toBeVisible()
  })
})
