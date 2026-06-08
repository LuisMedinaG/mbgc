import { test, expect } from '../fixtures/auth'
import { goToFirstGame } from '../helpers/nav'

test.describe('Game detail page', () => {
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
