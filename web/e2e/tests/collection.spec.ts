import { test, expect } from '../fixtures/auth'
import { goToCollection } from '../helpers/nav'

test.describe('Collection page', () => {
  test('renders heading and total count', async ({ authenticatedPage: page }) => {
    await goToCollection(page)
    await expect(page.getByRole('heading', { name: 'Board Game Collection' })).toBeVisible()
    // The fixture has 3 games, header should show "3 games" or similar
    await expect(page.getByText(/3 games/)).toBeVisible()
  })

  test('lists all games as links to /games/:id', async ({ authenticatedPage: page }) => {
    await goToCollection(page)
    const links = page.locator('a[href*="/games/"]')
    await expect(links).toHaveCount(3)
  })

  test('navigates to game detail on first link click', async ({ authenticatedPage: page }) => {
    await goToCollection(page)
    await page.locator('a[href*="/games/"]').first().click()
    await expect(page).toHaveURL(/\/games\/\d+/, { timeout: 8000 })
  })

  test('empty state shows when API returns zero games', async ({ page }) => {
    // Use a fresh page (not authenticatedPage) — install empty mocks manually.
    await page.route('**/api/v1/auth/refresh', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { access_token: 'mock.jwt.refreshed' } }) }))
    await page.route('**/api/v1/ping', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { pong: true, username: 'testuser' } }) }))
    await page.route('**/api/v1/profile', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { id: 'u1', username: 't', bgg_username: 't', is_admin: false } }) }))
    await page.route('**/api/v1/games*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 20, total: 0 } }) }))
    await page.route('**/api/v1/collections*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 0, total: 0 } }) }))
    await page.addInitScript(() => {
      localStorage.setItem('mbgc_access', 'mock.jwt.access')
      localStorage.setItem('mbgc_refresh', 'mock.jwt.refresh')
    })
    await page.goto('/')
    await expect(page.getByText(/no games|0 games|empty/i).first()).toBeVisible({ timeout: 10000 })
  })
})
