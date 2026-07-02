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
  └── SwiftData (on-device SQLite)
        Game     — @Attribute(.unique) bggId
        Collection — isDefault=true → Library (seeded on first launch)
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
│   ├── Collection.swift       @Model — isDefault=true reserved for Library
│   └── FinderFlow.swift       Tonight picker flow; per-question logic behind FinderAxis
├── Networking/
│   ├── BGGClient.swift        actor — fetchThings(ids:token:), 5s pacing, 4-attempt retry
│   ├── BGGXMLParser.swift     XMLParser delegate for /xmlapi2/thing XML
│   └── BGGGame.swift          Intermediate struct (mirrors Go importer.BGGGame)
├── ViewModels/
│   ├── VibesViewModel.swift   SwiftData CRUD for Collection (no API calls)
│   └── GameDetailViewModel.swift  Local-first: SwiftData CRUD (no API calls)
├── Views/
│   ├── ContentView.swift      Tab switcher — seeds Library on first launch
│   ├── LibraryView.swift      Discover tab — empty state placeholder
│   ├── VibesView.swift        Collection tab — @Query collections, CRUD sheets
│   ├── CsvImportView.swift    CSV → BGG fetch → SwiftData → calls onComplete
│   ├── ImportView.swift       Import page: side-by-side BGG/CSV modes, CollectionPickerView
│   ├── GameDetailView.swift   Detail — reads SwiftData cache, collection CRUD
│   ├── SearchView.swift       Search — local-first filtering via @Query
│   └── SettingsView.swift     Import links only
└── project.yml                XcodeGen config (iOS 17, Swift 6, bundle: app.lumedina.mbgc)
```

---

## Data model rules

### Game
- `@Attribute(.unique) var bggId: Int` — this is the **primary key** now, not a server `id`
- `init(bggGame: BGGGame)` — use for all local imports
- Fetch by bggId: `#Predicate { $0.bggId == someId }`

### Collection
- `isDefault: Bool` — `true` only for Library (seeded once in `ContentView.seedLibraryIfNeeded`)
- Library is sorted first via `createdAt = Date.distantPast`
- **Never delete or rename Library** — check `!collection.isDefault` before any destructive op
- Games are added to collections via `CollectionPickerView` after import — user picks the destination
- Smart collections (`isSmart == true`): `games` relationship stays empty — always resolve membership via `Collection.smartGames(collections:allGames:)`, never read `.games` directly (it silently reads as 0)

### BGG username
- Stored in `UserDefaults.standard` under key `"profile.bggUsername"`
- NOT stored in Keychain, NOT synced to backend

### BGG API token
- Optional build-time `BGGToken` from `Secrets.xcconfig` / `Info.plist`
- No user-entered token UI or Keychain storage exists yet
- Never store real tokens in repo files, `.env`, screenshots, or handoff docs

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
| Smart Filter editor (`SmartListEditor`) — base lists + combine/intersect/subtract/exclude, filters scoped to resolved set | ✅ Working (local-first) |

---

## Dead code to clean up (future pass)

| File / Symbol | Why dead | Cleanup action |
|---|---|---|
| — | — | None currently tracked |

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

## Design tokens

All visual constants live in `Views/DesignTokens.swift`. Use them for every UI change. No magic numbers in views.

| Token enum | What it covers |
|---|---|
| `Spacing` | `xs(4) sm(8) md(12) lg(16) xl(20) xxl(24) section(32) screen(24)` |
| `Radius` | `small(12) medium(16) large(24) xlarge(32) pill(999)` |
| `Typography` | `screenTitle sectionTitle cardTitle body bodyEmphasis metadata caption step tab` |
| `Surface` | `background card elevated separator metadataText` |
| `BrandAccent` | `color(.indigo) tint(.indigo @ 0.10)` |

Reusable components also in `DesignTokens.swift`: `GameMetadataRow`, `ChromeButton`, `SectionTitle`, `ScreenTitle`, `TagPill`, `SelectableCard`, `GameCoverImage`.

**Rule:** if you're hardcoding a `CGFloat`, `Color`, or `Font` that matches an existing token, use the token. Add new tokens rather than mutating existing ones — names are referenced by call sites.

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

**Finder questions stay behind `FinderAxis`.** Add a new Tonight picker question by
adding a `FinderAxis` case, a private `FinderQuestionKind` struct in
`Models/FinderFlow.swift`, and a `FinderConfig.funnel` entry. Do not introduce a
full factory/registration system until Finder needs runtime-configurable questions,
multi-select/free-text question types, or a larger question catalog.

**Do NOT add or call a backend API client.** Any new iOS data feature must go
through `BGGClient` or SwiftData directly.

**BGG rate limiting.** `BGGClient` paces requests at ~5s via `Task.sleep` (`requestDelay`).
Do not add parallel fetches without updating the rate-limit budget — BGG will 429/5xx the IP.
Import time is rate-limit-bound; benchmark it before tuning `requestDelay`. See DESIGN.md §3.1
for the timing model and the DEBUG per-request `Logger` / `Finished in X.Xs` instrumentation.

---

## BGG username sync (Implemented)

Sourced via `BGGClient.fetchCollection(username:token:)`:
- `GET https://boardgamegeek.com/xmlapi2/collection?username=X&own=1&brief=1`
- Returns `[Int]` (owned BGG IDs) — same 202-retry pattern as Go importer
- Diff against existing SwiftData `bggId`s
- Fetch missing metadata using `BGGClient.fetchThings(ids:token:onProgress:)`
- Insert `Game` objects → call `onComplete?(newGames)` → show `CollectionPickerView`
- Cooldown logic: gated to once per 7 days via `UserDefaults` (last sync date stored). In `DEBUG` builds the cooldown is skipped entirely (`#if !DEBUG` guard in `ImportView.importFromBGG()`) — run freely during development.
