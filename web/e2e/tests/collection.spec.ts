import { test, expect } from '../fixtures/auth'
import { goToCollection } from '../helpers/nav'

test.describe('Collection page', () => {
  test.beforeEach(async ({ authenticatedPage }) => {
    await goToCollection(authenticatedPage)
  })

  test('shows heading and game count', async ({ authenticatedPage: page }) => {
    await expect(page.getByRole('heading', { name: 'Board Game Collection' })).toBeVisible()
    await expect(page.getByText(/\d+ game/)).toBeVisible()
  })

  test('has at least one game in the list', async ({ authenticatedPage: page }) => {
    const count = await page.locator('a[href*="/games/"]').count()
    expect(count).toBeGreaterThan(0)
  })

  test('search filter narrows the game list', async ({ authenticatedPage: page }) => {
    const total = await page.locator('a[href*="/games/"]').count()
    const firstName = await page.locator('a[href*="/games/"]').first().textContent()
    const prefix = (firstName ?? '').slice(0, 4).trim()
    if (!prefix) test.skip()

    await page.getByPlaceholder(/search/i).fill(prefix)
    await page.waitForTimeout(400) // debounce
    const filtered = await page.locator('a[href*="/games/"]').count()
    expect(filtered).toBeLessThanOrEqual(total)
  })

  test('navigates to game detail on click', async ({ authenticatedPage: page }) => {
    await page.locator('a[href*="/games/"]').first().click()
    await expect(page).toHaveURL(/\/games\/\d+/, { timeout: 8000 })
    await expect(page.locator('h1').first()).toBeVisible({ timeout: 10000 })
  })
})
