import { test, expect } from '../fixtures/auth'
import { goToVibes } from '../helpers/nav'

test.describe('Vibes page', () => {
  test.beforeEach(async ({ authenticatedPage }) => {
    await goToVibes(authenticatedPage)
  })

  test('loads collection pills from API', async ({ authenticatedPage: page }) => {
    await expect(page.locator('button.pressable').first()).toBeVisible({ timeout: 8000 })
  })

  test('selecting a collection shows games or empty state', async ({ authenticatedPage: page }) => {
    await page.locator('button.pressable').first().click()
    await expect(
      page.locator('a[href*="/games/"]').first().or(page.getByText(/No games found/))
    ).toBeVisible({ timeout: 8000 })
  })
})
