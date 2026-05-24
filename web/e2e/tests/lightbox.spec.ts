import { test, expect } from '../fixtures/auth'
import { goToFirstGame } from '../helpers/nav'

test.describe('Player aid lightbox', () => {
  test('thumbnail click opens and Escape closes lightbox', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    const aidCount = await page.locator('button[style*="cursor: pointer"] img').count()
    if (aidCount === 0) {
      test.skip()
      return
    }

    await page.locator('button[style*="cursor: pointer"] img').first().click()
    await expect(page.locator('div[style*="position: fixed"]')).toBeVisible()
    await page.keyboard.press('Escape')
    await expect(page.locator('div[style*="position: fixed"]')).not.toBeVisible()
  })
})
