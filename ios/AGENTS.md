# AGENTS.md — MBGC iOS

iOS app for MBGC. **Local-first.** No login, no backend calls. Data comes from
BGG's public XML API and is stored on-device via SwiftData.

> **Last updated:** 2026-06-25 — Sessions 1–5 complete. Full import flow with destination picker.
> Full change log: `docs/handoff/2026-06-25-ios-local-first.md`

---

## Architecture

```
iOS app
  │
  ├── BGGClient  ──────────────────────▶  BGG XML API (Bearer token)
  │     fetchThings(ids:)                 https://boardgamegeek.com/xmlapi2/thing
  │     fetchCollection(username:token:)
  │
  ├── Keychain (BGG API token only)
  │
  ├── SwiftData (on-device SQLite)
  │     Game     — @Attribute(.unique) bggId
  │     Collection — isDefault=true → Library (seeded on first launch)
  │
  └── APIClient  ──────────────────────▶  services/api  ← DEAD CODE
        All methods return 401.             (no JWT, no login)
        Do NOT re-enable or call these.
```

**services/api is NOT used by the iOS app.** It still runs on Cloud Run for the
web app. The iOS app is fully decoupled from the backend.

---

## Stack

- Swift 6.2, iOS 17+, SwiftUI, SwiftData, URLSession async/await
- `@Observable` everywhere — never `ObservableObject`, `@StateObject`, Combine
- XcodeGen for project file generation
- Zero third-party dependencies

---

## Directory

```
ios/MBGC/
├── MBGCApp.swift              App entry — modelContainer([Game, Collection])
├── Models/
│   ├── Game.swift             @Model — bggId is @Attribute(.unique) primary key
│   └── Collection.swift       @Model — isDefault=true reserved for Library
├── Networking/
│   ├── BGGClient.swift        actor — fetchThings(ids:token:), 5s pacing, 4-attempt retry
│   ├── BGGXMLParser.swift     XMLParser delegate for /xmlapi2/thing XML
│   ├── BGGGame.swift          Intermediate struct (mirrors Go importer.BGGGame)
│   └── Keychain.swift         BGG API token storage only
├── ViewModels/
│   ├── VibesViewModel.swift   SwiftData CRUD for Collection (no API calls)
│   ├── ProfileViewModel.swift BGG username → UserDefaults (no API calls)
│   └── GameDetailViewModel.swift  Local-first: SwiftData CRUD (no API calls)
├── Views/
│   ├── ContentView.swift      Tab switcher — seeds Library on first launch
│   ├── LibraryView.swift      Discover tab — empty state placeholder
│   ├── VibesView.swift        Collection tab — @Query collections, CRUD sheets
│   ├── CsvImportView.swift    CSV → BGG fetch → SwiftData → calls onComplete
│   ├── ImportView.swift       Import page: side-by-side BGG/CSV modes, CollectionPickerView
│   ├── GameDetailView.swift   Detail — reads SwiftData cache, collection CRUD
│   ├── SearchView.swift       Search — local-first filtering via @Query
│   └── ProfileView.swift      BGG username field, saves to UserDefaults
└── project.yml                XcodeGen config (iOS 17, Swift 6, bundle: app.lumedina.mbgc)
```

---

## Data model rules

### Game
- `@Attribute(.unique) var bggId: Int` — this is the **primary key** now, not a server `id`
- `init(bggGame: BGGGame)` — use for all local imports
- `init(dto: GameDTO)` — legacy path, maps `dto.bggId ?? dto.id` (kept for future re-sync)
- Fetch by bggId: `#Predicate { $0.bggId == someId }`

### Collection
- `isDefault: Bool` — `true` only for Library (seeded once in `ContentView.seedLibraryIfNeeded`)
- Library is sorted first via `createdAt = Date.distantPast`
- **Never delete or rename Library** — check `!collection.isDefault` before any destructive op
- Games are added to collections via `CollectionPickerView` after import — user picks the destination

### BGG username
- Stored in `UserDefaults.standard` under key `"profile.bggUsername"`
- NOT stored in Keychain, NOT synced to backend

### BGG API token
- Stored in iOS Keychain under key `"bgg.apiToken"`
- Never store in repo files, `.env`, screenshots, or handoff docs

---

## What works end-to-end

| Flow | Status |
|------|--------|
| CSV import → BGG fetch → destination picker → collection | ✅ Working |
| Import from BGG page — BGG username field, CSV button | ✅ Working |
| Collection picker — add games to any collection | ✅ Working |
| Collection tab — create / rename / delete | ✅ Working |
| Library collection — lists imported games | ✅ Working |
| Game detail — reads from SwiftData cache | ✅ Working (no network needed) |
| BGG username save / load | ✅ Working (UserDefaults) |
| Discover tab | ⏳ Placeholder |
| Search | ✅ Working (local-first @Query filter) |
| BGG username sync (full) | ✅ Working (local-first via BGG public API) |
| Vibes/Collections editing on game detail | ✅ Working (local-first via SwiftData) |

---

## Dead code to clean up (future pass)

| File / Symbol | Why dead | Cleanup action |
|---|---|---|
| `Keychain.swift` | Stores BGG API token | Keep |
| `Game.vibeNames`, `vibeCollectionIds` | Server-side vibes, unused locally | Delete after local vibes are built |

---

## Build commands

```sh
# Generate Xcode project (run after adding/removing Swift files)
xcodegen generate                  # from ios/

# Build (replace simulator ID with `xcrun simctl list devices available`)
xcodebuild -scheme MBGC \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  build

# Current booted simulator (2026-06-25)
# iPhone 17 Pro  AE64B0C3-C281-4517-A4C0-06523E7C6B95
```

---

## Critical rules

**NEVER modify `.pbxproj` or `.xcodeproj/` directory contents.**
Add Swift files to the filesystem, then run `xcodegen generate` in `ios/`.

**`@Observable` everywhere.** Never `ObservableObject`, `@StateObject`, Combine.

**SwiftData CRUD takes `ModelContext` as a parameter.** Do NOT use
`@Environment(\.modelContext)` inside a ViewModel — pass the context from the View.
Exception: sheets must be standalone `View` structs with their own
`@Environment(\.modelContext)` (SwiftUI doesn't reliably propagate context into computed
view properties used as sheet content).

**Do NOT call `APIClient` methods.** They all require a JWT that doesn't exist.
Any new data feature must go through `BGGClient` or SwiftData directly.

**BGG rate limiting.** `BGGClient` paces requests at ~5s via `Task.sleep`. Do not add
parallel fetches without updating the rate-limit budget — BGG will 429/5xx the IP.

---

## BGG username sync (Implemented)

Sourced via `BGGClient.fetchCollection(username:token:)`:
- `GET https://boardgamegeek.com/xmlapi2/collection?username=X&own=1&brief=1`
- Returns `[Int]` (owned BGG IDs) — same 202-retry pattern as Go importer
- Diff against existing SwiftData `bggId`s
- Fetch missing metadata using `BGGClient.fetchThings(ids:token:onProgress:)`
- Insert `Game` objects → call `onComplete?(newGames)` → show `CollectionPickerView`
- Cooldown logic: gated to once per 7 days via `UserDefaults` (last sync date stored).
