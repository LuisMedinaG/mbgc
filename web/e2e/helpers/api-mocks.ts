/**
 * Network-level mocks for all /api/v1/* routes.
 *
 * Two modes:
 *   - mockAll(page)  — install all routes against FIXTURE_* data
 *   - per-route overrides via individual helpers or page.route() in tests
 *
 * State (collections, games created via POST) is held in module-local arrays
 * so a single test can assert CRUD round-trips without re-mounting the app.
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
  {
    id: 3, bgg_id: 167791, name: 'Terraforming Mars',
    description: 'Card-driven engine builder', year_published: 2016,
    image: '', thumbnail: '', min_players: 1, max_players: 5,
    play_time: 120, categories: ['Science Fiction'], mechanics: ['Card Drafting'],
    types: ['Board Game'], weight: 3.27, rating: 8.3,
    language_dependence: 2, recommended_players: [2, 3],
    rules_url: null, vibes: [], player_aids: [],
  },
]

export const FIXTURE_COLLECTIONS = [
  { id: 1, user_id: 'user-1', name: 'Favourites', description: 'My top games', game_count: 2 },
  { id: 2, user_id: 'user-1', name: 'Party Games', description: '', game_count: 0 },
]

export const FIXTURE_PROFILE = {
  id: 'user-1',
  username: 'testuser',
  bgg_username: 'testuser',
  is_admin: false,
}

// Mutable state for the duration of a test. Tests can call resetState() to
// restore the defaults.
const state = {
  games: [...FIXTURE_GAMES],
  collections: [...FIXTURE_COLLECTIONS],
  profile: { ...FIXTURE_PROFILE },
  nextGameId: FIXTURE_GAMES.length + 1,
  nextCollectionId: FIXTURE_COLLECTIONS.length + 1,
}

export function resetState(): void {
  state.games = [...FIXTURE_GAMES]
  state.collections = [...FIXTURE_COLLECTIONS]
  state.profile = { ...FIXTURE_PROFILE }
  state.nextGameId = FIXTURE_GAMES.length + 1
  state.nextCollectionId = FIXTURE_COLLECTIONS.length + 1
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
    const url = route.request().url()
    if (route.request().method() !== 'GET') return route.continue()
    // List endpoint has no path segment after /games (or has ?query)
    // e.g. /api/v1/games or /api/v1/games?limit=20
    // Exclude detail URLs like /api/v1/games/1
    if (/\/api\/v1\/games\/\d+/.test(url)) return route.fallback()
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: state.games,
        meta: { page: 1, limit: 20, total: state.games.length },
      }),
    })
  })
}

/** Mock GET /api/v1/games/:id (also handles PUT collections + DELETE) */
export async function mockGetGame(page: Page): Promise<void> {
  // Use a wide-net pattern (matches anything with /games/) and self-filter.
  // This is more reliable than relying on Playwright glob edge cases.
  await page.route('**/api/v1/games/**', (route) => {
    const url = route.request().url()
    // Only handle paths that have an ID after /games/
    if (!/\/api\/v1\/games\/\d+/.test(url)) return route.fallback()
    const match = url.match(/\/api\/v1\/games\/(\d+)/)
    if (!match) return route.fallback()
    const id = Number(match[1])
    const game = state.games.find(g => g.id === id)
    if (!game) {
      return route.fulfill({
        status: 404,
        contentType: 'application/json',
        body: JSON.stringify({ error: { code: 'NOT_FOUND', message: 'not found' } }),
      })
    }
    if (route.request().method() === 'GET') {
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ data: { ...game, player_aids: [], vibeCollectionIds: [] } }),
      })
    }
    return route.fallback()
  })
}

/** Mock DELETE /api/v1/games/:id */
export async function mockDeleteGame(page: Page): Promise<void> {
  await page.route(/\/api\/v1\/games\/\d+$/, (route) => {
    if (route.request().method() !== 'DELETE') return route.fallback()
    const url = route.request().url()
    const id = Number(url.match(/\/api\/v1\/games\/(\d+)/)![1])
    const idx = state.games.findIndex(g => g.id === id)
    if (idx >= 0) state.games.splice(idx, 1)
    return route.fulfill({ status: 204 })
  })
}

/** Mock full /api/v1/collections CRUD */
export async function mockCollections(page: Page): Promise<void> {
  await page.route('**/api/v1/collections*', (route) => {
    const method = route.request().method()
    if (method === 'GET') {
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: state.collections,
          meta: { page: 1, limit: state.collections.length, total: state.collections.length },
        }),
      })
    }
    if (method === 'POST') {
      const body = JSON.parse(route.request().postData() ?? '{}')
      const created = {
        id: state.nextCollectionId++,
        user_id: 'user-1',
        name: body.name ?? '',
        description: body.description ?? '',
        game_count: 0,
      }
      state.collections.push(created)
      return route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({ data: created }),
      })
    }
    const m = route.request().url().match(/\/api\/v1\/collections\/(\d+)/)
    if (m) {
      const id = Number(m[1])
      const idx = state.collections.findIndex(c => c.id === id)
      if (idx < 0) {
        return route.fulfill({
          status: 404,
          contentType: 'application/json',
          body: JSON.stringify({ error: { code: 'NOT_FOUND', message: 'not found' } }),
        })
      }
      if (method === 'PUT') {
        const body = JSON.parse(route.request().postData() ?? '{}')
        state.collections[idx] = { ...state.collections[idx], ...body }
        return route.fulfill({ status: 204 })
      }
      if (method === 'DELETE') {
        state.collections.splice(idx, 1)
        return route.fulfill({ status: 204 })
      }
    }
    return route.continue()
  })
}

/** Mock GET /api/v1/profile + PUT /api/v1/profile/bgg-username */
export async function mockProfile(page: Page): Promise<void> {
  await page.route('**/api/v1/profile', (route) => {
    if (route.request().method() !== 'GET') return route.continue()
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ data: state.profile }),
    })
  })
  await page.route('**/api/v1/profile/bgg-username', (route) => {
    if (route.request().method() !== 'PUT') return route.continue()
    const body = JSON.parse(route.request().postData() ?? '{}')
    state.profile = { ...state.profile, bgg_username: body.bgg_username ?? '' }
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ data: state.profile }),
    })
  })
}

/** Mock POST /api/v1/import/sync (BGG sync) */
export async function mockBGGSync(
  page: Page,
  opts: { status?: number; body?: object; error?: string } = {},
): Promise<void> {
  const status = opts.status ?? 200
  await page.route('**/api/v1/import/sync', (route) => {
    if (status === 200) {
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ data: opts.body ?? { imported: 3, skipped: 0, failed: 0 } }),
      })
    }
    return route.fulfill({
      status,
      contentType: 'application/json',
      body: JSON.stringify({ error: { code: 'INTERNAL_ERROR', message: opts.error ?? 'sync failed' } }),
    })
  })
}

/** Mock POST /api/v1/import/csv/preview + POST /api/v1/import/csv */
export async function mockCSVImport(page: Page): Promise<void> {
  await page.route('**/api/v1/import/csv/preview', (route) => {
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        data: {
          rows: [
            { bgg_id: 174430, name: 'Gloomhaven', already_owned: false },
            { bgg_id: 13, name: 'Catan', already_owned: false },
          ],
          total_rows: 2,
          preview_limit: 100,
        },
        meta: { page: 1, limit: 2, total: 2 },
      }),
    })
  })
  await page.route('**/api/v1/import/csv', (route) => {
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ data: { imported: 2, failed: 0 } }),
    })
  })
}

// ── Catch-all ──────────────────────────────────────────────────────────────────

/**
 * Install all API mocks. Call in `test.beforeEach` for a fully offline run.
 * Individual mocks override the catch-all for their specific route.
 *
 * State is NOT reset between tests — call `resetState()` in beforeEach if
 * your test mutates collections/games.
 */
export async function mockAll(page: Page): Promise<void> {
  process.stderr.write('[api-mocks] mockAll called\n')

  // Playwright LIFO: last-registered runs first. Register the broad
  // OPTIONS preflight handler FIRST so it runs LAST. Then register
  // specific routes AFTER so they run FIRST and shadow the preflight
  // for matching URLs (only OPTIONS preflight falls through).
  await page.route('**/api/v1/**', (route) => {
    if (route.request().method() === 'OPTIONS') {
      return route.fulfill({
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Authorization, Content-Type',
          'Access-Control-Max-Age': '86400',
        },
      })
    }
    // Unmocked GET/POST/PUT/DELETE on /api/v1/* — fall through to the
    // network so the browser surfaces a real connection error.
    return route.fallback()
  })

  // Specific routes — registered AFTER the catch-all, so they run FIRST in LIFO.
  await mockAuthLogin(page)
  await mockAuthLogout(page)
  await mockAuthRefresh(page)
  await mockPing(page)
  await mockProfile(page)
  // mockListGames uses a glob `**/api/v1/games*` that ALSO matches
  // `/api/v1/games/:id`. It self-filters and continues for those.
  await mockListGames(page)
  // mockGetGame has a tighter pattern for detail URLs — register it AFTER
  // mockListGames so its glob wins in LIFO.
  await mockGetGame(page)
  await mockDeleteGame(page)
  await mockCollections(page)
  await mockBGGSync(page)
  await mockCSVImport(page)
}
