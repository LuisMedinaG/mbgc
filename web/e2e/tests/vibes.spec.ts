import { test, expect } from '../fixtures/auth'
import { goToVibes } from '../helpers/nav'
import { resetState } from '../helpers/api-mocks'

test.describe('Vibes page — CRUD', () => {
  test.beforeEach(() => { resetState() })

  test('renders existing collections as pills', async ({ authenticatedPage: page }) => {
    await goToVibes(page)
    await expect(page.getByText('Favourites').first()).toBeVisible()
    await expect(page.getByText('Party Games').first()).toBeVisible()
  })

  test('creating a vibe sends POST and the new pill appears', async ({ authenticatedPage: page }) => {
    const postPromise = page.waitForRequest(
      (req) => req.url().includes('/api/v1/collections') && req.method() === 'POST',
    )
    await goToVibes(page)
    await page.getByRole('button', { name: 'Edit' }).click()
    await page.getByPlaceholder(/new vibe/i).fill('Co-op')
    await page.getByRole('button', { name: '+ Add' }).click()
    const req = await postPromise
    expect(req.method()).toBe('POST')
    expect(JSON.parse(req.postData() ?? '{}').name).toBe('Co-op')
    await expect(page.getByText('Co-op').first()).toBeVisible({ timeout: 5000 })
  })

  test('failed create shows backend error message, not [object Object]', async ({ page }) => {
    resetState()
    await page.route('**/api/v1/collections*', (route) => {
      if (route.request().method() === 'POST') {
        return route.fulfill({
          status: 422,
          contentType: 'application/json',
          body: JSON.stringify({ error: { code: 'VALIDATION_FAILED', message: 'name too long' } }),
        })
      }
      if (route.request().method() === 'GET') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ data: [], meta: { page: 1, limit: 0, total: 0 } }),
        })
      }
      return route.continue()
    })
    // Other auth/ping mocks for boot
    await page.route('**/api/v1/ping', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { pong: true, username: 't' } }) }))
    await page.route('**/api/v1/profile', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { id: 'u1', username: 't', bgg_username: 't', is_admin: false } }) }))
    await page.route('**/api/v1/games*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 20, total: 0 } }) }))
    await page.route('**/api/v1/auth/refresh', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { access_token: 'mock.jwt.refreshed' } }) }))

    await page.addInitScript(() => {
      localStorage.setItem('mbgc_access', 'mock.jwt.access')
      localStorage.setItem('mbgc_refresh', 'mock.jwt.refresh')
    })
    await page.goto('/#/vibes')
    await expect(page.getByRole('heading', { name: 'Browse by Vibe' })).toBeVisible({ timeout: 8000 })
    await page.getByRole('button', { name: 'Edit' }).click()
    await page.getByPlaceholder(/new vibe/i).fill('x'.repeat(300))
    await page.getByRole('button', { name: '+ Add' }).click()
    // CRITICAL: the bug from earlier showed "[object Object]" — assert we see the real message.
    await expect(page.getByText('name too long')).toBeVisible({ timeout: 5000 })
    await expect(page.getByText('[object Object]')).not.toBeVisible()
  })

  test('renaming a vibe sends PUT', async ({ authenticatedPage: page }) => {
    const putPromise = page.waitForRequest(
      (req) => /\/api\/v1\/collections\/\d+$/.test(req.url()) && req.method() === 'PUT',
    )
    await goToVibes(page)
    await page.getByRole('button', { name: 'Edit' }).click()
    // Click the Favourites pill (in manage mode, the button shows ✎ + name and enters edit on click)
    await page.locator('button:has-text("Favourites")').first().click()
    // Now the textbox is visible with the current name pre-filled
    const textbox = page.getByRole('textbox').first()
    await textbox.fill('Top Picks')
    // The save button is ✓ — find it within the editing pill container
    await page.locator('button:has-text("✓")').first().click()
    const req = await putPromise
    expect(JSON.parse(req.postData() ?? '{}').name).toBe('Top Picks')
  })

  test('deleting a vibe sends DELETE after confirmation', async ({ authenticatedPage: page }) => {
    const delPromise = page.waitForRequest((req) =>
      req.url().includes('/api/v1/collections/') && req.method() === 'DELETE',
    )
    await goToVibes(page)
    await page.getByRole('button', { name: 'Edit' }).click()
    // Click the X on the first pill
    await page.getByRole('button', { name: '✕' }).first().click()
    // Confirm
    await page.getByRole('button', { name: 'Delete' }).first().click()
    const req = await delPromise
    expect(req.url()).toMatch(/\/api\/v1\/collections\/\d+/)
  })
})

test.describe('Vibes page — discover', () => {
  test.beforeEach(() => { resetState() })

  test('selecting a collection triggers /discover and shows games', async ({ authenticatedPage: page }) => {
    const discoverPromise = page.waitForRequest('**/api/v1/discover*')
    await goToVibes(page)
    await page.getByText('Favourites').first().click()
    const req = await discoverPromise
    expect(req.url()).toContain('collection_id=1')
  })

  test('selecting a collection with no games shows empty state', async ({ authenticatedPage: page }) => {
    // Override /discover to return empty
    await page.route('**/api/v1/discover*', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ data: { data: [], total: 0, collection: { id: 2, name: 'Party Games', description: '', game_count: 0 } } }),
      }),
    )
    await goToVibes(page)
    await page.getByText('Party Games').first().click()
    await expect(page.getByText(/No games found/i)).toBeVisible({ timeout: 5000 })
  })
})
