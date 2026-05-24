import { test, expect } from '../fixtures/auth'
import { goToCollection } from '../helpers/nav'

test.describe('Tab navigation', () => {
  test('Collection tab active on root', async ({ authenticatedPage: page }) => {
    await goToCollection(page)
    await expect(page.getByRole('heading', { name: 'Board Game Collection' })).toBeVisible()
  })

  test('Vibes tab navigates to vibes page', async ({ authenticatedPage: page }) => {
    await goToCollection(page)
    await page.getByRole('link', { name: /vibes/i }).click()
    await expect(page.getByRole('heading', { name: 'Browse by Vibe' }))
      .toBeVisible({ timeout: 8000 })
  })

  test('Collection tab navigates back from vibes', async ({ authenticatedPage: page }) => {
    await page.goto('/#/vibes')
    await expect(page.getByRole('heading', { name: 'Browse by Vibe' }))
      .toBeVisible({ timeout: 8000 })
    await page.getByRole('link', { name: /collection/i }).click()
    await expect(page.getByRole('heading', { name: 'Board Game Collection' }))
      .toBeVisible({ timeout: 8000 })
  })
})
