# iOS Local-First Handoff

**Date:** 2026-06-25
**Status:** Sessions 1–6 complete. All screens local. Only APIClient.swift and ImportViewModel.swift are dead code. Option A (BGG username sync) already wired in ImportView — just needs backend to be bypassed.

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

**No screen calls `APIClient` anymore.** All data paths are local (SwiftData or BGGClient).

Dead files safe to delete in one cleanup commit:
| File | Reason |
|------|--------|
| `ios/MBGC/Networking/APIClient.swift` | Entire file — all callers removed |
| `ios/MBGC/ViewModels/ImportViewModel.swift` | `ImportView` manages its own state inline; this VM is never instantiated |

Still alive (not dead):
| File | Why kept |
|------|----------|
| `ios/MBGC/Networking/Keychain.swift` | Used by `ImportView` to persist the BGG API token securely |

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

---

## What was done (Session 3 — Collection model, profile fixes, UI)

### Bug fixes

| Bug | Root cause | Fix |
|-----|-----------|-----|
| Can't create collections | `ContentView.createSheet` was a computed property that captured `self.modelContext` — SwiftUI didn't reliably propagate that context into the presented sheet | Extracted `CreateCollectionSheet` as a standalone `View` struct with its own `@Environment(\.modelContext)` |
| Can't save BGG username | `ProfileViewModel.saveBGG()` called `APIClient.shared.setBGGUsername()` which requires a JWT | Replaced with `UserDefaults.standard.set(forKey: "profile.bggUsername")` |
| `seedLibraryIfNeeded` crash risk | `#Predicate { $0.isDefault == true }` can be unstable for Bool properties in SwiftData | Replaced with `fetch(FetchDescriptor<Collection>())` + in-memory `.filter { $0.isDefault }` |

### New: `Collection` SwiftData model

New file `ios/MBGC/Models/Collection.swift`:
- `@Model class Collection` — `name`, `desc`, `isDefault`, `createdAt`
- `isDefault = true` → Library (seeded once, undeletable, sorted first via `createdAt = .distantPast`)
- `@Relationship(deleteRule: .nullify, inverse: \Game.collections) var games: [Game]`
- `Game.collections: [Collection]` added (many-to-many inverse)
- `MBGCApp.modelContainer(for: [Game.self, Collection.self])`

**Rename:** `Collection` DTO in `APIClient.swift` → `CollectionDTO` to avoid naming conflict.

### Collection tab — full local CRUD

`VibesViewModel.swift` rewritten — synchronous SwiftData methods, no API calls:
- `create(name:description:modelContext:)` → `modelContext.insert(Collection(...))`
- `update(_:name:description:modelContext:)` → mutate + save
- `delete(_:modelContext:)` → guard `!isDefault`, then `modelContext.delete` + save
- Collections driven by `@Query(sort: \Collection.createdAt)` in `VibesView`

**Rename / Rename sheets:** extracted as standalone `View` structs (`CreateCollectionSheet`, `RenameCollectionSheet`) — each has its own `@Environment(\.modelContext)`.

### Collection page UI

`VibesView.swift` redesigned:
- Custom `.largeTitle.bold()` "Collection" header (not NavigationBar title)
- Each row: colored icon (Library = blue grid, user = orange folder) | name | Spacer | count (number only, `.title3.semibold`)
- Library row has lock icon; swipe actions hidden for `isDefault` collections
- `CollectionDetailView` reads `collection.games` directly — no API call

### Profile

- `ProfileView` — Account section removed (no server-side username)
- `ProfileViewModel.load()` — reads BGG username from `UserDefaults`
- `ProfileViewModel.saveBGG()` — synchronous, writes to `UserDefaults`
- Save button correctly disabled when input is empty or unchanged

### CSV import — Library assignment

`CsvImportView.importCSV()` now adds newly imported games to the Library collection:
```swift
let library = modelContext.fetch(FetchDescriptor<Collection>())
    .first { $0.isDefault }
library?.games.append(contentsOf: newGames)
```

### What works after Session 3

| Flow | Status |
|------|--------|
| CSV import → BGG fetch → Library | ✅ |
| Collection tab — create / rename / delete | ✅ |
| Library collection — lists imported games | ✅ |
| Game detail — reads SwiftData cache | ✅ |
| BGG username save / load | ✅ (UserDefaults) |
| Discover tab | ⏳ Placeholder |
| Search | ❌ APIClient → 401 |
| BGG username sync | ❌ Option A not yet built |

---

## What was done (Session 4 — UI polish)

### Settings — single "Import from BGG" entry point

`SettingsView.swift` simplified to two rows: "Import from BGG" and "Profile". No split menus.

`ImportView.swift` restructured as a single `List`:
- **Section 1:** BGG sync placeholder (coming soon) with icon + error display
- **Section 2:** "Import from CSV" as a button that presents `CsvImportView` as a sheet (no push navigation)
- Title: "Import from BGG", `.navigationBarTitleDisplayMode(.large)`

### HomePillView — larger pills with icons

`pillButton` now uses `Label(label, systemImage: icon)`:
- Discover: `binoculars.fill`
- Collection: `square.stack.fill`

Size increases:
| Before | After |
|--------|-------|
| `.subheadline` font | `.body` font |
| `padding(.horizontal, 16)` | `padding(.horizontal, 20)` |
| `padding(.vertical, 10)` | `padding(.vertical, 12)` |

### VibesView — more top space

Title top padding increased from `8pt` → `32pt` for a more spacious header.

---

## What was done (Session 4 — UI polish)

### HomePillView — icon on top, small text

Pills redesigned as `VStack(spacing: 4)` with icon above label:
- Discover: `binoculars.fill` + "Discover"
- Collection: `square.stack.fill` + "Collection"
- Icon: `.system(size: 20)`, text: `.caption2`

### Settings — Import from BGG + Import from CSV

Two independent rows. No Profile link. "Import from CSV" opens `CsvImportView` as a sheet directly from Settings.

### Import/Settings — consolidated navigation

`SettingsView` → "Import from BGG" (pushes `ImportView`) or "Import from CSV" (sheet).

---

## What was done (Session 5 — Import flow redesign)

### ImportView — new "Import from BGG" page

Full redesign of `ImportView` as the entry point for all imports:
- BGG username text field at the top (not stored, not linked to Profile)
- **Import via BGG** — primary filled button (disabled / coming soon — `bggUsername.isEmpty` guard)
- **Import via CSV** — secondary outlined button → opens `CsvImportView` as sheet
- After CSV import completes → `onComplete` callback → `CollectionPickerView` presented as sheet

### CsvImportView — no auto-Library assignment

- Removed the `library.games.append(contentsOf: newGames)` + save step
- Now calls `onComplete?(importedGames)` when done — parent drives the destination
- "Add to a collection…" button shown in `doneContent` step (only when `importedGames` is non-empty)

### CollectionPickerView — destination selector sheet

New inline `View` in `ImportView.swift`:
- Presented as a `.sheet` after CSV import completes
- `List` of all collections with icon, name, and current game count
- Tapping a collection: adds games to it, saves, dismisses both sheets
- "Cancel" dismisses without saving

### Flow summary

```
Settings → "Import from BGG" (ImportView)
  ├── Enter BGG username
  ├── "Import via BGG" (disabled — Option A)
  └── "Import via CSV" → CsvImportView (sheet)
        ├── Choose CSV → Preview → Import
        └── "Add to a collection…" → CollectionPickerView (sheet)
              ├── Tap Library / Collection name
              └── Games added → both sheets dismiss
```

---

## What was done (Session 3b — documentation)

Unified all project docs to reflect the local-first iOS architecture:

| File | Change |
|------|--------|
| `ios/AGENTS.md` | Full rewrite — architecture diagram, data model rules, dead code map, Option A spec |
| `README.md` | Updated architecture table, added iOS row pointing to BGG; added Xcode/XcodeGen to prerequisites; updated commands |
| `CLAUDE.md` | Updated Request Flow section — split web and iOS flows; updated directory tree |
| `.handoff/ios-status.md` | Marked SUPERSEDED with pointer to handoff doc |
| `.handoff/ios-api-needs.md` | Marked SUPERSEDED — iOS no longer calls services/api |

---

---

## What was done (Session 6 — SearchView, GameDetailView, GameDetailViewModel)

Last session to complete Option D. Rewired the two remaining APIClient callers to local SwiftData and deleted `LibraryViewModel`.

### Files changed

| File | Change |
|------|--------|
| `ios/MBGC/Views/SearchView.swift` | Rewritten: `@Query<Game>(sort: \Game.name)` + in-memory `localizedCaseInsensitiveContains` filter. No network call, no loading state, no APIClient. Removed "recent games" (session-only, no persistence). |
| `ios/MBGC/ViewModels/GameDetailViewModel.swift` | Rewritten: `var game: Game?` (SwiftData model, not DTO). `load()` is now synchronous. All mutations (collections, rulesUrl, delete) are SwiftData saves. No APIClient. Uses `PersistentIdentifier` for collection selection in edit mode. |
| `ios/MBGC/Views/GameDetailView.swift` | Updated to work with `Game` directly instead of `GameDetailDTO`. "Vibes" section → "Collections" section, backed by `@Query<Collection>`. `deleteGame` is now synchronous (no Task wrapper needed). Fixed field name: `game.gameDescription` (was `game.description`). Categories/mechanics use `?? []` since `Game` stores them as optional. |
| `ios/MBGC/ViewModels/LibraryViewModel.swift` | **Deleted** — LibraryView is a stub; no callers remain. |

### App screen status after Session 6

| Screen | Status | Notes |
|--------|--------|-------|
| Discover tab | ⏳ Placeholder | "Coming soon" — future random-pick feature |
| Collection tab | ✅ | `@Query<Collection>`, full CRUD, Library seeded on first launch |
| Collection detail | ✅ | `collection.games` SwiftData relationship |
| Search | ✅ | `@Query<Game>` local filter, instant |
| Game detail | ✅ | Reads from SwiftData, edits collections locally, deletes locally |
| Import (BGG username) | ✅ | `BGGClient.fetchCollection` + `fetchThings` → SwiftData (7-day cooldown, Keychain token) |
| Import (CSV) | ✅ | Local CSV parse → `BGGClient.fetchThings` → SwiftData |
| Collection picker (post-import) | ✅ | `CollectionPickerView` in `ImportView.swift` |
| Settings | ✅ | Import only (no Profile link, no logout) |
| Profile | ✅ | BGG username persisted to `UserDefaults` |

### Architecture notes

- `GameDetailViewModel.game` is now `Game?` (SwiftData `@Model`) — not `GameDetailDTO?`. The view reads fields directly off the model.
- Collection membership (formerly "vibes") is a SwiftData many-to-many relationship: `Game.collections ↔ Collection.games`. Editing uses `PersistentIdentifier` for stable identity across SwiftData context.
- `SearchView` filtering is in-memory — fine for local libraries (hundreds of games). If libraries exceed ~5,000 games, add `#Predicate` with a server-side index instead.

---

## References

- BGG XML API docs: `https://boardgamegeek.com/wiki/page/BGG_XML_API2`
- Go importer reference: `services/api/internal/importer/bgg.go` — same field mapping used in `BGGXMLParser.swift`
- SwiftData models: `ios/MBGC/Models/Game.swift`, `ios/MBGC/Models/Collection.swift`
- BGG client: `ios/MBGC/Networking/BGGClient.swift`
- XML parser: `ios/MBGC/Networking/BGGXMLParser.swift`
- iOS agent rules: `ios/AGENTS.md`
