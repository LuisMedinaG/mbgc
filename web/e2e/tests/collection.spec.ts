import { test, expect } from '../fixtures/auth'
import { goToCollection } from '../helpers/nav'
import { mockAll, resetState } from '../helpers/api-mocks'

test.describe('Collection page', () => {
  test.beforeEach(() => { resetState() })

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
    // Use a fresh page (not authenticatedPage) — install empty mocks via the
    // new override API. This is the same surface a developer would use for
    // any "what if the user has no games" test.
    await mockAll(page, { games: { empty: true }, collections: { empty: true } })
    await page.addInitScript(() => {
      localStorage.setItem('mbgc_access', 'mock.jwt.access')
      localStorage.setItem('mbgc_refresh', 'mock.jwt.refresh')
    })
    await page.goto('/')
    await expect(page.getByText(/no games|0 games|empty/i).first()).toBeVisible({ timeout: 10000 })
  })

  // ref: collection.SEARCH.1 — text search filters games by name
  test('search input filters list and sends ?q= after debounce', async ({ authenticatedPage: page }) => {
    const searchPromise = page.waitForRequest(
      (req) => req.url().includes('/api/v1/games') && req.url().includes('q=Glo'),
    )
    await goToCollection(page)
    await page.getByPlaceholder(/search games/i).fill('Glo')
    const req = await searchPromise
    // Assert the request shape — not just the UI — so a regression that
    // drops the query param is caught here, not in production.
    expect(req.method()).toBe('GET')
    expect(new URL(req.url()).searchParams.get('q')).toBe('Glo')
    // The mock filters state.games to only Gloomhaven on ?q=Glo
    await expect(page.getByText('Gloomhaven').first()).toBeVisible({ timeout: 5000 })
    await expect(page.getByText('Pandemic Legacy')).not.toBeVisible()
  })

  // ref: collection.API.1 — filter bar category select triggers ?category=
  test('selecting a category filter sends ?category= and narrows the list', async ({ authenticatedPage: page }) => {
    const categoryPromise = page.waitForRequest(
      (req) => req.url().includes('/api/v1/games') && req.url().includes('category=Medical'),
    )
    await goToCollection(page)
    // The FilterBar <select> has no aria-label; its accessible name comes
    // from the first <option> ("All categories"). Match by that.
    await page.locator('select.filter-select').first().selectOption('Medical')
    const req = await categoryPromise
    expect(new URL(req.url()).searchParams.get('category')).toBe('Medical')
    // Pandemic Legacy: Season 1 has category "Medical" in the fixture
    await expect(page.getByText('Pandemic Legacy: Season 1').first()).toBeVisible({ timeout: 5000 })
    await expect(page.getByText('Gloomhaven')).not.toBeVisible()
  })

  // ref: collection.API.1 — players filter sends ?players= and narrows the list
  test('selecting a players filter sends ?players=5plus and narrows to games supporting 5+', async ({ authenticatedPage: page }) => {
    const reqPromise = page.waitForRequest(
      (req) => req.url().includes('/api/v1/games') && req.url().includes('players=5plus'),
    )
    await goToCollection(page)
    await page.locator('select.filter-select').nth(1).selectOption('5plus')
    const req = await reqPromise
    expect(new URL(req.url()).searchParams.get('players')).toBe('5plus')
    // Only Terraforming Mars supports up to 5 players in the fixture.
    await expect(page.getByText('Terraforming Mars').first()).toBeVisible({ timeout: 5000 })
    await expect(page.getByText('Gloomhaven')).not.toBeVisible()
    await expect(page.getByText('Pandemic Legacy')).not.toBeVisible()
  })

  // ref: collection.ACTIVE_FILTERS.1 — clicking × on a filter chip clears it
  // and the list re-renders with the unfiltered set.
  // Note: TanStack Query dedupes identical query keys, so a "refetch" may
  // not produce a new HTTP request when the cleared filter is structurally
  // the same as the initial empty filter. We assert on the visible state
  // (3 games + chip removed) instead, which is the actual user-visible
  // behavior we care about.
  test('clicking × on an active filter chip removes it and re-renders the full list', async ({ authenticatedPage: page }) => {
    await goToCollection(page)
    // Apply a category filter first
    const applyPromise = page.waitForRequest(
      (req) => req.url().includes('/api/v1/games') && req.url().includes('category=Adventure'),
    )
    await page.locator('select.filter-select').first().selectOption('Adventure')
    await applyPromise

    // Wait for the filter chip to render.
    const chipRemove = page.getByRole('button', { name: /remove category filter/i })
    await expect(chipRemove).toBeVisible({ timeout: 5000 })
    // List narrowed to Adventure-only (Gloomhaven).
    await expect(page.getByText('Pandemic Legacy')).not.toBeVisible()

    // Click × — chip disappears, list returns to all games.
    await chipRemove.click()
    await expect(chipRemove).not.toBeVisible({ timeout: 5000 })
    await expect(page.getByText('Gloomhaven').first()).toBeVisible()
    await expect(page.getByText('Pandemic Legacy: Season 1').first()).toBeVisible()
    await expect(page.getByText('Terraforming Mars').first()).toBeVisible()
  })
})
