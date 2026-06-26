import type { Game } from '../types/game'

const BASE = (import.meta.env.VITE_API_BASE_URL ?? '') + '/api/v1'

// ── Access-token memory ──────────────────────────────────────────────────────
// Refresh tokens are stored by the API in an HttpOnly cookie, not in web storage.
let accessToken: string | null = null

export const tokens = {
  getAccess:  () => accessToken,
  setAccess:  (t: string) => { accessToken = t },
  clear() { accessToken = null },
}

// ── Error ──────────────────────────────────────────────────────────────────────
export class ApiError extends Error {
  readonly status: number
  constructor(status: number, message: string) {
    super(message)
    this.name = 'ApiError'
    this.status = status
  }
}

// ── Auth failure hook (called when refresh token is also expired) ─────────────
let onAuthFailureCb: (() => void) | null = null
export function setOnAuthFailure(cb: () => void) { onAuthFailureCb = cb }

// ── Core fetch with auto-refresh ───────────────────────────────────────────────
// ref: auth.TOKEN_REFRESH.1 — on 401, uses refresh token to get new access token
// ref: auth.TOKEN_REFRESH.2 — retries original request with new access token
// ref: auth.TOKEN_REFRESH.3 — coalesces concurrent refresh attempts
let refreshPromise: Promise<void> | null = null

function ensureRefreshPromise(): Promise<void> {
  if (!refreshPromise) {
    refreshPromise = request<{ data: { access_token: string } }>(
      'POST', '/auth/refresh', undefined, false,
    ).then(r => {
      tokens.setAccess(r.data.access_token)
    }).catch(err => {
      tokens.clear()
      onAuthFailureCb?.()
      throw err
    }).finally(() => {
      refreshPromise = null
    })
  }
  return refreshPromise
}

async function request<T>(
  method: string,
  path: string,
  body?: unknown,
  retry = true,
): Promise<T> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  const token = tokens.getAccess()
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch(BASE + path, {
    method,
    headers,
    credentials: 'include',
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })

  // Auto-refresh on 401 — coalesce concurrent requests into one refresh attempt
  if (res.status === 401 && retry) {
    await ensureRefreshPromise()
    return request<T>(method, path, body, false)
  }

  if (res.status === 204) return undefined as T

  const json = await res.json()
  if (!res.ok) {
    const msg = typeof json.error === 'string' ? json.error : json.error?.message ?? 'request failed'
    throw new ApiError(res.status, msg)
  }
  return json as T
}

// Multipart upload with auto-refresh (no Content-Type header — browser sets boundary)
async function upload<T>(path: string, formData: FormData, retry = true): Promise<T> {
  const headers: Record<string, string> = {}
  const token = tokens.getAccess()
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch(BASE + path, {
    method: 'POST',
    headers,
    credentials: 'include',
    body: formData,
  })

  // Auto-refresh on 401 — coalesce concurrent requests into one refresh attempt
  if (res.status === 401 && retry) {
    await ensureRefreshPromise()
    return upload<T>(path, formData, false)
  }

  if (res.status === 204) return undefined as T

  const json = await res.json()
  if (!res.ok) {
    const msg = typeof json.error === 'string' ? json.error : json.error?.message ?? 'request failed'
    throw new ApiError(res.status, msg)
  }
  return json as T
}

// ── API response types (Go → snake_case) ──────────────────────────────────────
interface CollectionAPI { id: number; name: string; description: string; game_count?: number }
interface PlayerAidAPI  { id: number; game_id: number; filename: string; label: string }

interface GameAPI {
  id:                   number
  bgg_id:               number
  name:                 string
  description:          string
  year_published:       number
  image:                string
  thumbnail:            string
  min_players:          number
  max_players:          number
  play_time:            number
  categories:           string | string[]
  mechanics:            string | string[]
  types:                string | string[]
  weight:               number
  rating:               number
  language_dependence:  number
  recommended_players:  string | number[]
  rules_url:            string
  vibes:                CollectionAPI[]  // backend still sends "vibes" key for now
  player_aids?:         PlayerAidAPI[]
}

// ── Mapper: snake_case API → camelCase Game ────────────────────────────────────
function splitCsv(v: string | string[] | null | undefined): string[] {
  if (Array.isArray(v)) return v
  if (typeof v === 'string') return v.split(',').map(s => s.trim()).filter(Boolean)
  return []
}

function splitCsvNumbers(v: string | number[] | null | undefined): number[] {
  if (Array.isArray(v)) return v
  if (typeof v === 'string') return v.split(',').map(s => parseInt(s.trim(), 10)).filter(n => !isNaN(n))
  return []
}

function mapGame(g: GameAPI): Game {
  return {
    id:                 g.id,
    bggId:              g.bgg_id,
    name:               g.name,
    description:        g.description,
    yearPublished:      g.year_published,
    image:              g.image,
    thumbnail:          g.thumbnail,
    minPlayers:         g.min_players,
    maxPlayers:         g.max_players,
    playTime:           g.play_time,
    categories:         splitCsv(g.categories),
    mechanics:          splitCsv(g.mechanics),
    types:              splitCsv(g.types),
    weight:             g.weight,
    rating:             g.rating,
    languageDependence: g.language_dependence,
    recommendedPlayers: splitCsvNumbers(g.recommended_players),
    rulesUrl:           g.rules_url,
    vibes:              (g.vibes ?? []).map(v => v.name),
  }
}

// ── Public types ───────────────────────────────────────────────────────────────
export interface Collection {
  id:          number
  name:        string
  description: string
  gameCount:   number
}

export interface PlayerAid {
  id: number
  gameId: number
  filename: string
  label: string
}

export interface GameDetail extends Game {
  playerAids: PlayerAid[]
  vibeCollectionIds: number[]
}

export interface GamesListParams {
  q?:           string
  category?:    string
  players?:     string
  playtime?:    string
  weight?:      string
  rating?:      string
  lang?:        string
  rec_players?: string
  page?:        number
  limit?:       number
}

export interface GamesListResponse {
  data:       Game[]
  total:      number
  page:       number
  per_page:   number
  categories: string[]
}

export interface DiscoverResponse {
  data:       Game[]
  total:      number
  collection: Collection
}

export interface SyncResult {
  imported:      number
  skipped:       number
  failed:        number
  imported_ids?: number[]
}

export interface BGGPreviewResult {
  total: number
  owned: number
  new:   number
}

export interface CSVPreviewRow {
  bgg_id:        number
  name:          string
  already_owned: boolean
}

export interface CSVPreviewResult {
  rows:          CSVPreviewRow[]
  total_rows:    number
  preview_limit: number
}

export interface CSVImportResult {
  imported: number
  failed:   number
}

export interface DiscoverParams {
  collection_id: number
  type?:         string
  category?:     string
  mechanic?:     string
  players?:      string
  playtime?:     string
  weight?:       string
  rating?:       string
  lang?:         string
  rec_players?:  string
}

// ── API methods ────────────────────────────────────────────────────────────────
export const api = {
  // Auth
  async login(username: string, password: string) {
    const r = await request<{ data: { access_token: string; expires_in: number } }>(
      'POST', '/auth/login', { username, password }, false,
    )
    tokens.setAccess(r.data.access_token)
    return r.data
  },

  async logout() {
    await request('POST', '/auth/logout', undefined, false).catch(() => {})
    tokens.clear()
  },

  async ping() {
    const r = await request<{ data: { pong: boolean; username: string } }>('GET', '/ping')
    return r.data
  },

  // Games
  async listGames(params: GamesListParams = {}): Promise<GamesListResponse> {
    const qs = new URLSearchParams()
    for (const [k, v] of Object.entries(params)) {
      if (v !== undefined && v !== '') qs.set(k, String(v))
    }
    const suffix = qs.size ? `?${qs}` : ''
    const r = await request<{ data: GameAPI[]; total: number; page: number; per_page: number; categories: string[] }>(
      'GET', `/games${suffix}`,
    )
    return { ...r, data: r.data.map(mapGame) }
  },

  async getGame(id: number): Promise<GameDetail> {
    const r = await request<{ data: GameAPI & { player_aids: PlayerAidAPI[] } }>('GET', `/games/${id}`)
    return {
      ...mapGame(r.data),
      playerAids: (r.data.player_aids ?? []).map(a => ({
        id:       a.id,
        gameId:   a.game_id,
        filename: a.filename,
        label:    a.label,
      })),
      vibeCollectionIds: (r.data.vibes ?? []).map(v => v.id),
    }
  },

  async deleteGame(id: number) {
    return request('DELETE', `/games/${id}`)
  },

  async setGameCollections(gameId: number, collectionIds: number[]) {
    return request<{ data: { game_id: number; collection_ids: number[] } }>(
      'POST', `/games/${gameId}/collections`, { collection_ids: collectionIds },
    )
  },

  async bulkCollections(gameIds: number[], collectionIds: number[]) {
    return request<{ data: { updated: number } }>(
      'POST', '/games/bulk-collections', { game_ids: gameIds, collection_ids: collectionIds },
    )
  },

  // Collections
  async listCollections(): Promise<Collection[]> {
    const r = await request<{ data: CollectionAPI[] }>('GET', '/collections')
    return r.data.map(c => ({
      id:          c.id,
      name:        c.name,
      description: c.description,
      gameCount:   c.game_count ?? 0,
    }))
  },

  async createCollection(name: string, description = ''): Promise<Collection> {
    const r = await request<{ data: CollectionAPI }>('POST', '/collections', { name, description })
    return { id: r.data.id, name: r.data.name, description: r.data.description, gameCount: 0 }
  },

  async updateCollection(id: number, name: string, description = ''): Promise<Collection> {
    const r = await request<{ data: CollectionAPI }>('PUT', `/collections/${id}`, { name, description })
    return { id: r.data.id, name: r.data.name, description: r.data.description, gameCount: 0 }
  },

  async deleteCollection(id: number) {
    return request('DELETE', `/collections/${id}`)
  },

  // Discover
  async discover(params: DiscoverParams): Promise<DiscoverResponse> {
    const qs = new URLSearchParams()
    for (const [k, v] of Object.entries(params)) {
      if (v !== undefined && v !== '') qs.set(k, String(v))
    }
    const r = await request<{ data: GameAPI[]; total: number; collection: CollectionAPI }>(
      'GET', `/discover?${qs}`,
    )
    return {
      data:  r.data.map(mapGame),
      total: r.total,
      collection: {
        id:          r.collection.id,
        name:        r.collection.name,
        description: r.collection.description,
        gameCount:   r.collection.game_count ?? 0,
      },
    }
  },

  // Profile
  async getProfile() {
    const r = await request<{ data: { username: string; bgg_username: string } }>('GET', '/profile')
    return r.data
  },

  async setBGGUsername(bggUsername: string) {
    return request<void>('PUT', '/profile/bgg-username', { bgg_username: bggUsername })
  },

  async changePassword(currentPassword: string, newPassword: string) {
    return request<void>('PUT', '/profile/password', {
      current_password: currentPassword,
      new_password:     newPassword,
    })
  },

  // Files
  async updateRulesUrl(gameId: number, rulesUrl: string) {
    const r = await request<{ data: { game_id: number; rules_url: string } }>(
      'PUT', `/games/${gameId}/rules-url`, { rules_url: rulesUrl },
    )
    return r.data
  },

  async uploadPlayerAid(gameId: number, file: File, label: string): Promise<PlayerAid> {
    const fd = new FormData()
    fd.append('file', file)
    fd.append('label', label)
    const r = await upload<{ data: PlayerAidAPI }>(`/games/${gameId}/player-aids`, fd)
    return { id: r.data.id, gameId: r.data.game_id, filename: r.data.filename, label: r.data.label }
  },

  async deletePlayerAid(gameId: number, aidId: number) {
    return request('DELETE', `/games/${gameId}/player-aids/${aidId}`)
  },

  // Import
  async previewBGG(): Promise<BGGPreviewResult> {
    const r = await request<{ data: BGGPreviewResult }>('POST', '/import/bgg/preview', undefined)
    return r.data
  },

  async syncBGG(fullRefresh = false): Promise<SyncResult> {
    const path = fullRefresh ? '/import/sync?full_refresh=true' : '/import/sync'
    const r = await request<{ data: SyncResult }>('POST', path, undefined)
    return r.data
  },

  async csvPreview(file: File): Promise<CSVPreviewResult> {
    const fd = new FormData()
    fd.append('csv_file', file)
    const r = await upload<{ data: CSVPreviewResult }>('/import/csv/preview', fd)
    return r.data
  },

  async csvImport(bggIds: number[]): Promise<CSVImportResult> {
    const r = await request<{ data: CSVImportResult }>('POST', '/import/csv', { bgg_ids: bggIds })
    return r.data
  },
}
