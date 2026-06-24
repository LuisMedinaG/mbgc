import { test, expect } from '../fixtures/auth'
import { goToFirstGame } from '../helpers/nav'
import { resetState } from '../helpers/api-mocks'

test.describe('Game detail page', () => {
  test.beforeEach(() => { resetState() })

  test('renders game name in h1 and stats labels', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    const heading = page.locator('h1').first()
    await expect(heading).toBeVisible()
    const name = (await heading.textContent())?.trim() ?? ''
    expect(name.length).toBeGreaterThan(0)
    await expect(page.getByText('Players', { exact: false }).first()).toBeVisible()
    await expect(page.getByText('Playtime', { exact: false }).first()).toBeVisible()
  })

  test('has BoardGameGeek external link', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await expect(page.getByRole('link', { name: /boardgamegeek/i })).toBeVisible()
  })

  test('vibes section edit/cancel round-trips without saving', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await page.getByRole('button', { name: 'Edit' }).click()
    await expect(page.getByRole('button', { name: 'Save' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Cancel' })).toBeVisible()
    await page.getByRole('button', { name: 'Cancel' }).click()
    await expect(page.getByRole('button', { name: 'Edit' })).toBeVisible()
  })

  // ref: game-detail.VIBE_ASSIGN.2 — checking a vibe and saving sends a POST
  // with the full collection ID set, and the pill appears without a reload.
  test('assigning a vibe sends POST and the pill appears', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await expect(page.getByText('No vibes assigned.')).toBeVisible()
    const postPromise = page.waitForRequest(
      (req) => /\/api\/v1\/games\/\d+\/collections$/.test(req.url()) && req.method() === 'POST',
    )
    await page.getByRole('button', { name: 'Edit' }).click()
    await page.getByText('Favourites').click()
    await page.getByRole('button', { name: 'Save' }).click()
    const refetchPromise = page.waitForResponse(
      (res) => /\/api\/v1\/games\/\d+$/.test(res.url()) && res.request().method() === 'GET',
    )
    const req = await postPromise
    expect(JSON.parse(req.postData() ?? '{}').collection_ids).toEqual([1])
    await refetchPromise
    await expect(page.locator('.vibe-pill', { hasText: 'Favourites' })).toBeVisible({ timeout: 5000 })
    await expect(page.getByRole('button', { name: 'Edit' })).toBeVisible()
  })

  test('rules URL editor rejects non-Drive URLs', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await page.getByTitle('Edit rulebook URL').click()
    await page.getByPlaceholder(/drive\.google\.com/i).fill('https://example.com/rules.pdf')
    await page.getByRole('button', { name: 'Save' }).click()
    await expect(page.getByText(/google drive/i)).toBeVisible()
    await page.getByRole('button', { name: 'Cancel' }).click()
  })

  test('delete confirmation can be cancelled', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await page.getByRole('button', { name: 'Delete game' }).click()
    await expect(page.getByRole('button', { name: /yes, delete/i })).toBeVisible()
    await page.getByRole('button', { name: 'Cancel' }).last().click()
    await expect(page.getByRole('button', { name: 'Delete game' })).toBeVisible()
  })

  test('player aids section shows upload affordance', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await expect(page.getByText('Player Aids', { exact: false }).first()).toBeVisible()
  })
})
