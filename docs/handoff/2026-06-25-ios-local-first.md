# iOS Local-First Handoff

**Date:** 2026-06-25
**Status:** Option D complete — CSV import working. Option A (BGG username sync) is next.

---

## What was done (Session 1 — login removal)

Removed mandatory login from the iOS app. The app now opens directly into Discover (local SwiftData read), no auth gate. Login UI + AuthViewModel deleted.

**Files changed:**
- `MBGCApp.swift` — removed `AuthViewModel`, removed `RootView` auth gate
- `ContentView.swift` — default tab changed from `.collection` → `.discover`
- `SettingsView.swift` — removed Log Out button
- `LibraryView.swift` — rewritten: `@Query<Game>` from SwiftData, empty state, ShareLink (native share sheet)
- `LoginView.swift` — deleted
- `AuthViewModel.swift` — deleted

**Files neutralized (compile but do nothing on appear):**
- `VibesViewModel.load()` — no longer calls `APIClient.shared.listCollections()`
- `ImportViewModel.load()` — no longer calls `APIClient.shared.getProfile()`
- `ProfileViewModel.load()` — no longer calls `APIClient.shared.getProfile()`

---

## What was done (Session 2 — Option D: CSV → BGG → SwiftData)

Implemented Option D: CSV file import that fetches game metadata directly from BGG's public XML API and stores it locally in SwiftData. No backend, no auth, no API keys.

### New files

| File | Purpose |
|------|---------|
| `ios/MBGC/Networking/BGGGame.swift` | Intermediate struct mirroring Go's `importer.BGGGame` |
| `ios/MBGC/Networking/BGGXMLParser.swift` | SAX-style `XMLParser` delegate for `/xmlapi2/thing` response |
| `ios/MBGC/Networking/BGGClient.swift` | `actor BGGClient` — fetches `/thing` in batches of 20, 2 RPS rate limit, 4-attempt exponential-backoff retry |

### Modified files

| File | Change |
|------|--------|
| `ios/MBGC/Models/Game.swift` | `id` field removed; `bggId` is now `@Attribute(.unique)`. Added `init(bggGame:)` and `update(from bggGame:)`. Kept `init(dto:)` / `update(from dto:)` for legacy server path. |
| `ios/MBGC/Views/CsvImportView.swift` | Fully rewritten: local CSV parsing, BGG `/thing` fetch, SwiftData write. Removed all `APIClient` calls. Shows per-batch progress during import. |
| `ios/MBGC/Views/ImportView.swift` | Removed broken BGG sync result block. BGG username sync section now shows "coming soon" message. CSV import link unchanged. |
| `ios/MBGC/ViewModels/ImportViewModel.swift` | Removed `SyncResult` dependency. `sync()` now returns a "coming soon" message instead of calling the API. |
| `ios/MBGC/Views/LibraryView.swift` | `GameDetailView(gameId: game.bggId)` — updated to use `bggId` (was `id`). |
| `ios/MBGC/ViewModels/GameDetailViewModel.swift` | `fetchLocalGame` predicate updated to `$0.bggId == gameId`. |
| `ios/MBGC/ViewModels/LibraryViewModel.swift` | `byId` dictionary key updated to `$0.bggId`. |

### What works today

- App opens → Discover tab (empty, shows "Import your collection" prompt)
- Settings → Import → CSV Import: choose a BGG CSV export → preview game list → import → fetches metadata from BGG → games appear in Discover immediately
- Discover list → tap a game → detail view (reads from SwiftData, no network needed)
- Discover list → Share button → native iOS share sheet (game list as plain text)
- Settings → Import → BGG Sync: shows "coming soon" message (not wired yet)
- Settings → Profile: BGG username field visible but save still calls broken API

### How CSV import works

1. User exports their BGG collection: `My Collection → Export` (produces a CSV with `objectid`, `objectname` columns)
2. User taps "Import from CSV" in Settings → Import
3. App parses the CSV locally — extracts `objectid` column, skips games already in SwiftData
4. `BGGClient.fetchThings(ids:)` calls `https://boardgamegeek.com/xmlapi2/thing?id=X,Y,Z&stats=1` in batches of 20 with a 2 RPS rate limit
5. `BGGXMLParser` parses the XML into `BGGGame` structs (same field mapping as the Go importer)
6. Each `BGGGame` is inserted as a `Game` SwiftData object; `modelContext.save()` commits the batch
7. Done screen shows imported / skipped / failed counts

### Architecture decisions

- **`Game.bggId` is now the unique key** (was server-side `id`). All local reads use `bggId`. The legacy `init(dto:)` path maps `dto.bggId ?? dto.id → Game.bggId` so server-synced data still works.
- **`BGGClient` is an `actor`** — thread-safe, shared singleton. The `onProgress` callback is `@Sendable (Int, Int) -> Void`; callers wrap `@MainActor` updates in `Task { @MainActor in ... }`.
- **No BGG auth** — the `/xmlapi2/thing` endpoint is fully public. `BGGClient` sends no credentials, no API key.
- **Deduplication** — `existingBggIds` fetches all local games and filters in memory (SwiftData `#Predicate` doesn't support `Array.contains` with runtime arrays).

---

## Remaining dead code

The auth plumbing in `APIClient.swift` is still present but unreachable. Clean it up in a future pass once all server-side paths are confirmed dead:
- `login()`, `refreshTokens()`, `logout()` (~35 lines)
- 401 retry logic in `send()` (~20 lines)
- `Keychain.swift` (41 lines) — only used by the removed auth token storage
- `Tokens` enum

Screens still calling `APIClient` (all fail silently — no auth token):
- `SearchView` → `APIClient.listGames()` — needs Option A or Option C
- `GameDetailView` → `APIClient.getGame()` — falls back to SwiftData cache (works for locally imported games)
- `VibesView` create/update/delete → `APIClient.*Collection()` — needs local SwiftData Collection model
- `CollectionDetailView` → `APIClient.discover()` — needs local data
- `ProfileViewModel.saveBGG()` → `APIClient.setBGGUsername()` — needs Option A

---

## Options for the data layer

### Option A — Port BGG username sync to Swift (next step)

Pull the user's full owned collection from BGG using the `/collection` endpoint. This is the natural follow-on to Option D — the `BGGClient` and `BGGXMLParser` built here are reused directly.

**What to build:**
1. Add `fetchCollection(username:) → [Int]` to `BGGClient`
   - `GET https://boardgamegeek.com/xmlapi2/collection?username=<name>&own=1`
   - 202 retry loop (BGG queues large collections): poll every 1–5s until 200
2. Wire `ImportViewModel.sync()` to call `fetchCollection` → `fetchThings` → SwiftData upsert
3. Update `ProfileViewModel` to save BGG username to `UserDefaults` (no backend needed)
4. Update `ImportView` to show BGG username field + Sync button
5. Add a local SwiftData `Collection` model + rewrite `VibesViewModel` → local

**BGG reference:** same as Go's `FetchCollection` in `services/api/internal/importer/bgg.go`

**Complexity:** Medium (~300 lines). `BGGClient` and XML parser already done.

### Option B — Keep backend, add anonymous shared-token auth

_(See original notes — not recommended, token extractable from IPA.)_

### Option C — Add public (unauthenticated) read endpoints to services/api

_(See original notes — right long-term answer for multi-user product.)_

### Option D — CSV import ✅ DONE

---

## References

- BGG XML API docs: `https://boardgamegeek.com/wiki/page/BGG_XML_API2`
- Go importer reference: `services/api/internal/importer/bgg.go` — same field mapping used in `BGGXMLParser.swift`
- SwiftData model: `ios/MBGC/Models/Game.swift` — `init(bggGame:)` added
- BGG client: `ios/MBGC/Networking/BGGClient.swift`
- XML parser: `ios/MBGC/Networking/BGGXMLParser.swift`
