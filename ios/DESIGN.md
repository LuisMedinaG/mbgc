# MBGC iOS — Design Document

**Version:** 1.0 · **Date:** 2026-06-26  
**Stack:** Swift 6.2 · iOS 17+ · SwiftUI · SwiftData · zero third-party dependencies  
**Architecture:** Local-first. No login, no JWT, no backend API calls from iOS.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Data Model](#2-data-model)
3. [Networking Layer](#3-networking-layer)
4. [View Models](#4-view-models)
5. [View Hierarchy](#5-view-hierarchy)
6. [Key Data Flows](#6-key-data-flows)
7. [Cross-Cutting Concerns](#7-cross-cutting-concerns)
8. [Conventions & Constraints](#8-conventions--constraints)
9. [Known Issues & Technical Debt](#9-known-issues--technical-debt)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│  SwiftUI Views  (@State, @Query, @Environment)           │
│  ViewModels     (@Observable, @MainActor)                │
└────────────────────────────┬────────────────────────────┘
                             │ SwiftData operations
┌────────────────────────────▼────────────────────────────┐
│  SwiftData (on-device SQLite)                           │
│  Models: Game (@bggId unique), Collection               │
└────────────────────────────┬────────────────────────────┘
                             │ import only
┌────────────────────────────▼────────────────────────────┐
│  BGGClient (actor)                                      │
│  BGG XML API — /xmlapi2/collection, /xmlapi2/thing      │
│  2 RPS · batches of 20 · 4-attempt retry                │
└─────────────────────────────────────────────────────────┘
```

### Principles

- **No backend.** All reads and writes go through SwiftData. `services/api` is not called by any iOS code.
- **`@Observable` everywhere.** `ObservableObject`, `@StateObject`, and Combine are banned.
- **`@Query` for reactive lists.** ViewModels hold transient mutation state only; reactive lists live in Views via `@Query`.
- **ModelContext ownership.** ViewModels receive `ModelContext` as a parameter from the calling View. Standalone sheet Views use `@Environment(\.modelContext)` directly — SwiftUI cannot reliably propagate context into sheet computed properties.
- **No third-party dependencies.** `BGGClient`, `BGGXMLParser`, and all UI are first-party Swift.

---

## 2. Data Model

### 2.1 `Game` — `@Model final class`
`Models/Game.swift`

Primary persistent entity. One row per unique BGG game ID.

| Property | Type | Notes |
|---|---|---|
| `bggId` | `Int` | `@Attribute(.unique)` — natural key |
| `name` | `String` | |
| `yearPublished` | `Int?` | |
| `thumbnail` | `String?` | URL string |
| `image` | `String?` | URL string |
| `minPlayers` | `Int?` | |
| `maxPlayers` | `Int?` | |
| `playtime` | `Int?` | |
| `rulesUrl` | `String?` | User-editable |
| `gameDescription` | `String?` | |
| `categories` | `[String]?` | BGG category labels |
| `mechanics` | `[String]?` | BGG mechanic labels |
| `types` | `[String]?` | BGG subdomains |
| `weight` | `Double?` | BGG average complexity (1–5) |
| `rating` | `Double?` | BGG average rating (1–10) |
| `languageDependence` | `Int?` | Derived from poll votes (0–5) |
| `recommendedPlayers` | `[Int]?` | Derived from poll votes |
| `collections` | `[Collection]` | Many-to-many inverse; owned by `Collection.games` |

**Initializers:**
- `init(bggGame: BGGGame)` — primary import path; calls `apply(_:BGGGame)`.

**Mutation methods:**
- `update(from bggGame: BGGGame)` — re-applies all fields (used during re-sync).

---

### 2.2 `Collection` — `@Model final class`
`Models/Collection.swift`

User-defined group of games. The Library is the single default collection, seeded once on first launch.

| Property | Type | Notes |
|---|---|---|
| `name` | `String` | |
| `desc` | `String` | |
| `isDefault` | `Bool` | `true` → Library; cannot be deleted |
| `createdAt` | `Date` | `Date.distantPast` for Library (sorts first) |
| `games` | `[Game]` | `@Relationship(deleteRule: .nullify, inverse: \Game.collections)` |

**Invariant:** exactly one `Collection` with `isDefault == true` exists after first launch. `ContentView.seedLibraryIfNeeded()` enforces this on app start.

---

### 2.3 Relationships

```
Collection ◄──────────────── Game
   name                        bggId (unique)
   desc                        name
   isDefault                   ...
   games: [Game]  ←──(many-to-many)──► collections: [Collection]
```

SwiftData owns the join table implicitly via `@Relationship(inverse:)` on `Collection.games`.

---

### 2.4 Supporting Types

No backend DTO bridge types remain in the iOS app.

---

## 3. Networking Layer

### 3.1 `BGGClient` — `actor`
`Networking/BGGClient.swift`

Sole network interface. All calls go to BGG's public XML API. Concurrency-safe by actor isolation.

**Singleton:** `static let shared = BGGClient()`

**Rate-limiting:**
- `requestDelay = 5,000,000,000 ns` (5 s between requests)
- `batchSize = 20` IDs per `/thing` request
- `maxAttempts = 4` with exponential backoff

**URLSession config:** 30 s request timeout, 120 s resource timeout.

#### Methods

```swift
func fetchCollection(username: String, token: String? = nil) async throws -> [Int]
```
- `GET /xmlapi2/collection?username=X&own=1&brief=1`
- Retries on 202 (queued), 429, 5xx; respects `Retry-After`.
- Returns BGG object IDs for owned games.

```swift
func fetchThings(ids: [Int], token: String? = nil, onProgress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [BGGGame]
```
- Splits `ids` into batches of 20; calls `fetchBatch(_:token:)` per batch.
- `onProgress(done, total)` called after each batch.

```swift
private func fetchBatch(_ ids: [Int], token: String?) async throws -> [BGGGame]
```
- `GET /xmlapi2/thing?id=<csv-ids>&stats=1`
- Parses via `BGGXMLParser.parseThingResponse(_:)`.

**Auth:** `Authorization: Bearer <token>` added when token is non-empty.  
**User-Agent:** `app.lumedina.mbgc/1.0`

---

### 3.2 `BGGError` — `enum : Error, LocalizedError`

| Case | Meaning |
|---|---|
| `.badURL` | Failed URL construction |
| `.emptyResponse(ids: [Int])` | BGG returned no items |
| `.xmlParse(Error)` | Parse failure |
| `.http(status: Int)` | Non-2xx response; 401 = rejected token |
| `.transport(Error)` | URLSession network error |

---

### 3.3 `BGGGame` — `struct`
`Networking/BGGGame.swift`

Intermediate value produced by `BGGXMLParser`. All fields non-optional; zeros coerced to `nil` by `Game.apply(_:)`.

`bggId · name · description · yearPublished · image · thumbnail · minPlayers · maxPlayers · playTime · categories · mechanics · types · weight · rating · languageDependence · recommendedPlayers`

---

### 3.4 `BGGXMLParser` — `enum` (namespace)
`Networking/BGGXMLParser.swift`

Stateless SAX-style XML parsing via `Foundation.XMLParser`.

```swift
static func parseCollectionResponse(_ data: Data) throws -> [Int]
static func parseThingResponse(_ data: Data) throws -> [BGGGame]
```

**`CollectionDelegate`** — accumulates `objectid` attributes from `<item>` elements; deduplicates via `Set<Int>`.

**`ThingDelegate`** — full parser for `/thing` XML:
- Tracks `inItem`, `inStatistics`, `inRatings`, `currentPollName` to scope nested elements.
- Computes `languageDependence` from `language_dependence` poll (highest-vote level wins).
- Computes `recommendedPlayers` from `suggested_numplayers` poll (best + rec > notRec).
- Unescapes HTML entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&#039;`, `&nbsp;`).

---

## 4. View Models

### 4.1 `GameDetailViewModel` — `@MainActor @Observable final class`
`ViewModels/GameDetailViewModel.swift`

Manages `GameDetailView` state: loading, collection membership editing, rules URL editing, deletion. All operations are SwiftData — no network.

| Property | Type | Role |
|---|---|---|
| `game` | `Game?` | Loaded game; `nil` on error |
| `selectedCollectionIds` | `Set<PersistentIdentifier>` | Working set during collection edit |
| `isSaving` | `Bool` | Disables Save button |
| `isDeleting` | `Bool` | Disables delete confirm |
| `errorMessage` | `String?` | Shown instead of content |
| `showDeleteConfirm` | `Bool` | Two-step delete gate |
| `editingCollections` | `Bool` | Toggles inline collection picker |

| Method | What it does |
|---|---|
| `load(gameId:modelContext:)` | Fetches `Game` by `bggId` via `#Predicate` |
| `startEditingCollections()` | Seeds `selectedCollectionIds` from `game.collections` |
| `toggleCollection(_:)` | Insert/remove from `selectedCollectionIds` |
| `saveCollections(allCollections:modelContext:)` | Assigns filtered collections to `game.collections`; saves |
| `updateRulesUrl(_:modelContext:)` | Mutates `game?.rulesUrl`; saves |
| `deleteGame(modelContext:) -> Bool` | Deletes from context; returns `true` → caller dismisses |

---

### 4.2 `VibesViewModel` — `@MainActor @Observable final class`
`ViewModels/VibesViewModel.swift`

Thin CRUD wrapper for `Collection` objects. Reactive lists live in `VibesView` via `@Query` — this VM only holds mutation error state.

| Method | What it does |
|---|---|
| `create(name:description:modelContext:)` | Inserts new `Collection`; saves |
| `update(_:name:description:modelContext:)` | Mutates name/desc; saves |
| `delete(_:modelContext:)` | Guards `!collection.isDefault`; deletes; saves |

---

## 5. View Hierarchy

```
MBGCApp
└── ContentView                      ← Root. Tab switcher + floating nav pill
    ├── [tab: .discover] LibraryView ← Placeholder ("Discover Coming Soon")
    ├── [tab: .collection] VibesView ← Collection list
    │   ├── CollectionDetailView     ← Games in a collection
    │   │   └── GameDetailView       ← Full game detail
    │   ├── CreateCollectionSheet    ← New collection (standalone sheet)
    │   └── RenameCollectionSheet    ← Rename/re-desc (standalone sheet)
    ├── [sheet] SearchView           ← Full-screen local search
    │   └── GameDetailView
    └── [sheet] SettingsView         ← Import links only
        ├── ImportView               ← BGG username sync
        │   └── CollectionPickerView ← Add imported games to a collection
        └── CsvImportView            ← CSV file import
            └── CollectionPickerView
```

---

### 5.1 `ContentView`
`Views/ContentView.swift`

Root view. Seeds Library on first launch.

**State:** `tab: HomeTab` (`.discover` / `.collection`), `showSearch`, `showSettings`, `showCreate`

**Actions:**
- `seedLibraryIfNeeded()` — runs on `.task`; inserts `Collection(name: "Library", isDefault: true)` if none exist.
- Floating pill (`HomePillView`) switches `tab`.
- `+` button → `CreateCollectionSheet` (tab-specific; only shows on `.collection` tab).
- Search → `SearchView` sheet.
- Settings → `SettingsView` sheet.

---

### 5.2 `SearchView`
`Views/SearchView.swift`

Full-screen modal. Local search over all `Game` objects — no network.

**`@Query(sort: \Game.name)` → `allGames: [Game]`** — reactive, SwiftData-backed.

**Filtering:** `results` computed var: `allGames.filter { $0.name.localizedCaseInsensitiveContains(query) }`. No debounce — local only.

**Navigation:** `NavigationPath` with `.navigationDestination(for: Int.self)` → `GameDetailView(gameId:)`.

---

### 5.3 `GameDetailView`
`Views/GameDetailView.swift`

**Input:** `let gameId: Int`

**`@Query(sort: \Collection.createdAt)` → `allCollections: [Collection]`**

**ViewModel:** `@State private var viewModel = GameDetailViewModel()`; loaded via `.task { viewModel.load(gameId:modelContext:) }`.

**Private sections (all receive `game: Game`):**

| Section | Content |
|---|---|
| `heroImage(_:)` | `AsyncImage` + gradient + name/year/rating/weight/langDep badges |
| `statsRow(_:)` | Players / playtime / complexity cells |
| `descriptionSection(_:)` | `gameDescription` text |
| `tagsSection(_:)` | `FlowLayout` chips — categories (blue), mechanics (green) |
| `collectionsSection(_:)` | Chip display or inline checklist (`editingCollections`) |
| `linksSection(_:)` | `rulesUrl` link + BGG link |
| `deleteSection(_:)` | Two-step delete confirmation |

**`FlowLayout : Layout`** — custom wrapping layout for tag chips.

---

### 5.4 `VibesView`
`Views/VibesView.swift`

**`@Query(sort: \Collection.createdAt)` → `collections: [Collection]`**

List of collections. Swipe actions: delete (non-default only), rename → `RenameCollectionSheet`. Tap → `CollectionDetailView`.

**`CreateCollectionSheet` / `RenameCollectionSheet`** — standalone `struct : View` with own `@Environment(\.modelContext)`. Direct SwiftData mutations (no ViewModel).

**`CollectionDetailView`** — shows `collection.games`; navigates to `GameDetailView(gameId: game.bggId)`.

---

### 5.5 `ImportView`
`Views/ImportView.swift`

BGG sync UI. Reads BGG username from `UserDefaults["profile.bggUsername"]`. Enforces a 7-day cooldown (`UserDefaults["import.bgg.lastSyncDate"]`).

**Key constants:**
- `bggRegularImportLimit = 100` — max new games per sync
- `bggImportCooldown = 7 * 24 * 60 * 60` s

**Flow:** fetch collection IDs → diff against local → fetch metadata → insert → `CollectionPickerView`.
Debug builds intentionally bypass the cooldown for local development.

---

### 5.6 `CsvImportView`
`Views/CsvImportView.swift`

Multi-step CSV import: `upload → preview → importing → done`

**Steps:**
1. `.fileImporter` → user picks CSV file
2. `previewCSV()` — parse headers, extract `objectid`/`objectname` rows
3. `importCSV()` — diff against local, fetch BGG metadata via `BGGClient`, insert into SwiftData
4. Done screen + `CollectionPickerView`

**`parseCSV(_:)`** — finds `objectid` column (case-insensitive); RFC-4180-style tokenizer with quote handling.

---

### 5.7 `CollectionPickerView`
`Views/ImportView.swift`

Shared post-import destination picker used by both `ImportView` and `CsvImportView`.

**Input:** `let games: [Game]`, `let onDone: () -> Void`

`addToCollection(_:)` — deduplicates against existing `col.games` by `bggId`; appends new; saves; calls `onDone()`.

---

### 5.8 `SettingsView`
`Views/SettingsView.swift`

Two navigation links: "Import from BGG" → `ImportView`, "Import from CSV" → `CsvImportView`. No state.

---

## 6. Key Data Flows

### 6.1 BGG Sync (ImportView)

```
importFromBGG() async
  1. Read BGGToken from Bundle.main Info.plist["BGGToken"]
  2. Check 7-day cooldown (UserDefaults["import.bgg.lastSyncDate"])
  3. BGGClient.shared.fetchCollection(username:token:)
       → GET /xmlapi2/collection?username=X&own=1&brief=1
       → BGGXMLParser.parseCollectionResponse → [Int]
  4. existingBggIds(from:) — fetch all Game, return Set<Int>
  5. newIds = bggIds.filter { !existing.contains($0) }.prefix(100)
  6. BGGClient.shared.fetchThings(ids: newIds, token:, onProgress:)
       → batches of 20 → GET /xmlapi2/thing?id=...&stats=1
       → BGGXMLParser.parseThingResponse → [BGGGame]
  7. For each BGGGame: Game(bggGame:) → modelContext.insert → modelContext.save()
  8. UserDefaults["import.bgg.lastSyncDate"] = Date()
  9. showDestinationPicker = true → CollectionPickerView
 10. CollectionPickerView.addToCollection(_:) → col.games += newGames; save
```

### 6.2 CSV Import (CsvImportView)

```
previewCSV()
  1. startAccessingSecurityScopedResource()
  2. String(contentsOf: url, encoding: .utf8)
  3. parseCSV(_:) → [CSVRow] (bggId, name)
  4. step = .preview

importCSV()
  1. existingBggIds(from: rows.map(\.bggId))
  2. toFetch = newIds (not in SwiftData)
  3. BGGClient.shared.fetchThings(ids: toFetch)   ← no token
  4. Game(bggGame:) → insert → save
  5. step = .done → CollectionPickerView
```

### 6.3 Local Search (SearchView)

```
@Query → allGames: [Game]   (reactive, always current)
query: String (TextField binding)
results = allGames.filter { name.localizedCaseInsensitiveContains(query) }
Tap → navigationPath.append(game.bggId) → GameDetailView(gameId:)
```

### 6.4 Collection Membership Edit (GameDetailView)

```
startEditingCollections()
  selectedCollectionIds = Set(game.collections.map(\.persistentModelID))

toggleCollection(_ col: Collection)
  insert/remove col.persistentModelID

saveCollections(allCollections:modelContext:)
  game.collections = allCollections.filter { selectedCollectionIds.contains($0.persistentModelID) }
  modelContext.save()
```

### 6.5 App Launch — Library Seed

```
ContentView.task → seedLibraryIfNeeded()
  FetchDescriptor<Collection>()
  if none with isDefault == true:
    insert Collection(name: "Library", isDefault: true)  [createdAt = Date.distantPast]
    modelContext.save()
```

---

## 7. Cross-Cutting Concerns

### BGG API Token
- **Current:** optional build-time token read as `String?` from `Bundle.main` (`Info.plist` key `BGGToken = $(BGG_TOKEN)`). `nil` when build variable unset — BGGClient omits the `Authorization` header and the public BGG API still works.
- **CSV path:** `CsvImportView.importCSV()` calls `fetchThings(ids:)` with no token (same behaviour).
- **Private collections:** if a user has a private BGG collection, a token is required. No UI or Keychain storage currently exists to enter one.

### Image Caching
`MBGCApp.init()` overrides `URLCache.shared`:
- Memory: 50 MB · Disk: 200 MB
- `AsyncImage` reads from this cache automatically — no custom image loader needed.

### Rate Limiting (app-side)
- **BGG sync cooldown:** 7 days, enforced in `ImportView` via `UserDefaults`.
- **Debug builds:** cooldown is bypassed for local development.
- **BGGClient request delay:** 5 s between network requests, enforced by actor.

### Error Handling
- `BGGError.http(status: 401)` → human-readable "token rejected" message in `ImportView`.
- SwiftData save failures → `viewModel.errorMessage` shown in UI.
- ViewModel methods never throw; errors are caught and stored in `errorMessage`.

---

## 8. Conventions & Constraints

| Rule | Detail |
|---|---|
| Observable pattern | `@Observable` only — no `ObservableObject`, `@StateObject`, Combine |
| ModelContext passing | ViewModels get `ModelContext` as a parameter; sheet Views use `@Environment(\.modelContext)` |
| Reactive lists | `@Query` in Views — ViewModels never hold lists that mirror SwiftData queries |
| Xcode project | Never edit `.pbxproj` manually — use `xcodegen generate` in `ios/` |
| Swift version | Swift 6.2 strict concurrency — all actors/`@MainActor` must be consistent |
| Simulator target | iPhone 17 Pro (iPhone 16 Pro not available in current environment) |
| No third-party deps | All functionality is first-party; `Package.swift` must stay dependency-free |

---

## 9. Known Issues & Technical Debt

| Issue | File | Priority |
|---|---|---|
| No UI/Keychain storage for private-collection BGG tokens | `ImportView.swift` | Low — public collections work without one |
| CSV import path sends no auth token to BGGClient | `CsvImportView.swift:importCSV()` | Low — same as above |
| `LibraryView` is a placeholder stub | `Views/LibraryView.swift` | Roadmap |
| No unit tests for ViewModels or Views | — | Medium |
| BGG sync cooldown (7 days) enforced app-side only, not server-side for iOS | `ImportView.swift` | Low |
