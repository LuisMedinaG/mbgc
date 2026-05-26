/**
 * Network-level mocks for all /api/v1/* routes.
 *
 * Usage in a test (or beforeEach):
 *
 *   import { mockAll } from '../helpers/api-mocks'
 *   test.beforeEach(async ({ page }) => { await mockAll(page) })
 *
 * Individual mocks can be called separately to override specific endpoints
 * while keeping the rest handled by mockAll.
 */
import type { Page } from '@playwright/test'

// ── Fixture data ───────────────────────────────────────────────────────────────

export const FIXTURE_GAMES = [
  {
    id: 1, bgg_id: 174430, name: 'Gloomhaven',
    description: 'Dungeon crawler', year_published: 2017,
    image: '', thumbnail: '', min_players: 1, max_players: 4,
    play_time: 120, categories: ['Adventure'], mechanics: ['Deck Building'],
    types: ['Board Game'], weight: 3.86, rating: 8.8,
    language_dependence: 2, recommended_players: [2, 3, 4],
    rules_url: null, vibes: [], player_aids: [],
  },
  {
    id: 2, bgg_id: 161936, name: 'Pandemic Legacy: Season 1',
    description: 'Cooperative legacy game', year_published: 2015,
    image: '', thumbnail: '', min_players: 2, max_players: 4,
    play_time: 60, categories: ['Medical'], mechanics: ['Co-op'],
    types: ['Board Game'], weight: 2.83, rating: 8.6,
    language_dependence: 3, recommended_players: [4],
    rules_url: null, vibes: [], player_aids: [],
  },
]

export const FIXTURE_COLLECTIONS = [
  { id: 1, user_id: 'user-1', name: 'Favourites', description: 'My top games', game_count: 2 },
  { id: 2, user_id: 'user-1', name: 'Party Games', description: '', game_count: 0 },
]

export const FIXTURE_PROFILE = {
  id: 'user-1',
  bgg_username: 'testuser',
  is_admin: false,
}

// ── Individual mock helpers ────────────────────────────────────────────────────

/** Mock POST /api/v1/auth/login */
export async function mockAuthLogin(
  page: Page,
  opts: { status?: number; error?: string } = {},
): Promise<void> {
  const status = opts.status ?? 200
  await page.route('**/api/v1/auth/login', (route) => {
    if (status === 200) {
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: { access_token: 'mock.jwt.access', refresh_token: 'mock.jwt.refresh', expires_in: 900 },
        }),
      })
    }
    return route.fulfill({
      status,
      contentType: 'application/json',
      body: JSON.stringify({ error: { code: 'UNAUTHORIZED', message: opts.error ?? 'unauthorized' } }),
    })
  })
}

/** Mock POST /api/v1/auth/logout */
export async function mockAuthLogout(page: Page): Promise<void> {
  await page.route('**/api/v1/auth/logout', (route) =>
    route.fulfill({ status: 204 }),
  )
}

/** Mock POST /api/v1/auth/refresh */
export async function mockAuthRefresh(page: Page): Promise<void> {
  await page.route('**/api/v1/auth/refresh', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ data: { access_token: 'mock.jwt.refreshed' } }),
    }),
  )
}

/** Mock GET /api/v1/ping */
export async function mockPing(page: Page): Promise<void> {
  await page.route('**/api/v1/ping', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ data: { pong: true, username: 'testuser' } }),
    }),
  )
}

/** Mock GET /api/v1/games */
export async function mockListGames(page: Page): Promise<void> {
  await page.route('**/api/v1/games*', (route) => {
    if (route.request().method() !== 'GET') return route.continue()
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: FIXTURE_GAMES,
        meta: { page: 1, limit: 20, total: FIXTURE_GAMES.length },
      }),
    })
  })
}

/** Mock GET /api/v1/games/:id */
export async function mockGetGame(page: Page): Promise<void> {
  await page.route(/\/api\/v1\/games\/\d+$/, (route) => {
    if (route.request().method() !== 'GET') return route.continue()
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ data: { ...FIXTURE_GAMES[0], player_aids: [] } }),
    })
  })
}

/** Mock GET /api/v1/collections */
export async function mockListCollections(page: Page): Promise<void> {
  await page.route('**/api/v1/collections*', (route) => {
    if (route.request().method() !== 'GET') return route.continue()
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: FIXTURE_COLLECTIONS,
        meta: { page: 1, limit: 20, total: FIXTURE_COLLECTIONS.length },
      }),
    })
  })
}

/** Mock GET /api/v1/profile */
export async function mockGetProfile(page: Page): Promise<void> {
  await page.route('**/api/v1/profile', (route) => {
    if (route.request().method() !== 'GET') return route.continue()
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ data: FIXTURE_PROFILE }),
    })
  })
}

// ── Catch-all ──────────────────────────────────────────────────────────────────

/**
 * Install all API mocks. Call this in `test.beforeEach` for a fully offline
 * test run. Individual mocks override the catch-all for their specific route.
 */
export async function mockAll(page: Page): Promise<void> {
  await mockAuthLogin(page)
  await mockAuthLogout(page)
  await mockAuthRefresh(page)
  await mockPing(page)
  await mockListGames(page)
  await mockGetGame(page)
  await mockListCollections(page)
  await mockGetProfile(page)
}
