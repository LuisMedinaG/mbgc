import { test, expect } from '../fixtures/auth'
import { goToFirstGame } from '../helpers/nav'

test.describe('Game detail page', () => {
  test('renders hero with name and stats cards', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)

    const heading = page.locator('h1').first()
    await expect(heading).toBeVisible()
    const name = await heading.textContent()
    expect(name?.trim().length).toBeGreaterThan(0)

    await expect(page.getByText('Players')).toBeVisible()
    await expect(page.getByText('Playtime')).toBeVisible()
    await expect(page.getByText('Complexity')).toBeVisible()
  })

  test('shows BGG link', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await expect(page.getByRole('link', { name: /boardgamegeek/i })).toBeVisible()
  })

  test('player aids section has upload button', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await expect(page.getByText('Player Aids')).toBeVisible()
    await expect(page.getByText('+ Upload')).toBeVisible()
  })

  test('vibes section has edit button', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await expect(page.getByText('Vibes')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Edit' })).toBeVisible()
  })

  test('vibes edit shows save/cancel then cancels cleanly', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await page.getByRole('button', { name: 'Edit' }).click()
    await expect(page.getByRole('button', { name: 'Save' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Cancel' })).toBeVisible()
    await page.getByRole('button', { name: 'Cancel' }).click()
    await expect(page.getByRole('button', { name: 'Edit' })).toBeVisible()
  })

  test('rulebook row shows edit pencil', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await expect(page.getByText(/rulebook/i).first()).toBeVisible()
    await expect(page.getByTitle('Edit rulebook URL')).toBeVisible()
  })

  test('rules URL editor validates non-Drive URLs', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await page.getByTitle('Edit rulebook URL').click()
    await expect(page.getByPlaceholder(/drive\.google\.com/i)).toBeVisible()

    await page.getByPlaceholder(/drive\.google\.com/i).fill('https://example.com/rules.pdf')
    await page.getByRole('button', { name: 'Save' }).click()
    await expect(page.getByText(/google drive/i)).toBeVisible()

    await page.getByRole('button', { name: 'Cancel' }).click()
    await expect(page.getByTitle('Edit rulebook URL')).toBeVisible()
  })

  test('delete confirmation can be cancelled', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await page.getByRole('button', { name: 'Delete game' }).click()
    await expect(page.getByRole('button', { name: /yes, delete/i })).toBeVisible()
    await page.getByRole('button', { name: 'Cancel' }).last().click()
    await expect(page.getByRole('button', { name: 'Delete game' })).toBeVisible()
    await expect(page.getByRole('button', { name: /yes, delete/i })).not.toBeVisible()
  })

  test('back navigation returns to collection', async ({ authenticatedPage: page }) => {
    await goToFirstGame(page)
    await page.goBack()
    await expect(page).toHaveURL(/\/#\/$|#\/$|^\/$|localhost:5173\/$/)
  })
})
