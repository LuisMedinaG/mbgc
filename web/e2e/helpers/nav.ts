import { expect, type Page } from '@playwright/test'

/** Go to the collection and wait for at least one game link. */
export async function goToCollection(page: Page): Promise<void> {
  await page.goto('/')
  await expect(page.locator('a[href*="/games/"]').first()).toBeVisible({ timeout: 12000 })
}

/** Go to the first game's detail page. Returns the game's aria-label. */
export async function goToFirstGame(page: Page): Promise<string> {
  await goToCollection(page)
  const firstLink = page.locator('a[href*="/games/"]').first()
  const name = (await firstLink.getAttribute('aria-label')) ?? ''
  await firstLink.click()
  await expect(page).toHaveURL(/\/games\/\d+/, { timeout: 8000 })
  await expect(page.locator('h1').first()).toBeVisible({ timeout: 10000 })
  return name
}

/** Go to the vibes page and wait for its heading. */
export async function goToVibes(page: Page): Promise<void> {
  await page.goto('/#/vibes')
  await expect(page.getByRole('heading', { name: 'Browse by Vibe' })).toBeVisible({ timeout: 8000 })
}
