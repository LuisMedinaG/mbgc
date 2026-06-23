# iOS App Plan — MBGC (My Board Game Collection)

## Context

iOS native frontend for MBGC backend. Overboard.app as UX reference.
Same repo as Go API + React web (`mbgc/` monorepo).

## Stack

- SwiftUI + SwiftData + URLSession (no Apollo, no Combine, no third-party networking)
- Swift 6.2 / iOS 17+ deployment target
- XcodeGen for project generation
- Bun for npm package management
- Supabase Auth via hosted webview (no custom login UI)
- Offline-first: SwiftData persistence, mutations queue for API sync

## Architecture

```
ios/
├── MBGC/
│   ├── MBGCApp.swift           # App entry, SwiftData container, @MainActor
│   ├── Models/
│   │   └── Game.swift          # @Model class — id, name, thumbnail, yearPublished, isOwned, collections
│   │   └── SyncState.swift     # tracks pending API sync operations
│   ├── Networking/
│   │   └── APIClient.swift     # URLSession async/await, JWT Bearer header, typed errors
│   ├── ViewModels/
│   │   └── AuthViewModel.swift # @Observable — Supabase token, login state
│   │   └── LibraryViewModel.swift
│   │   └── GameDetailViewModel.swift
│   ├── Views/
│   │   ├── ContentView.swift   # TabView: Library, Discover, Search, Settings
│   │   ├── LibraryView.swift   # Grid of owned games from SwiftData, pull-to-refresh
│   │   ├── DiscoverView.swift  # /api/v1/discover
│   │   ├── SearchView.swift    # /api/v1/games?q=
│   │   ├── GameDetailView.swift
│   │   ├── ImportView.swift    # BGG username input → sync
│   │   ├── CSVImportView.swift # local CSV parse → SwiftData write
│   │   ├── SettingsView.swift  # BGG username, logout
│   │   └── LoginView.swift     # Supabase webview auth
│   └── Utilities/
│       └── CSVParser.swift     # pure local, no network
├── project.yml                 # XcodeGen config (NOT .pbxproj)
└── AGENTS.md                  # iOS-specific agent rules
```

## API Endpoints Used

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | /api/v1/games | Yes | List user's collection |
| GET | /api/v1/games/{id} | Yes | Game detail |
| DELETE | /api/v1/games/{id} | Yes | Remove from collection |
| POST | /api/v1/games/{id}/collections | Yes | Assign to collections |
| PUT | /api/v1/games/{id}/rules-url | Yes | Set rules URL |
| GET | /api/v1/collections | Yes | List collections |
| POST | /api/v1/collections | Yes | Create collection |
| PUT | /api/v1/collections/{id} | Yes | Update collection |
| DELETE | /api/v1/collections/{id} | Yes | Delete collection |
| GET | /api/v1/discover | Yes | Popular games |
| POST | /api/v1/import/sync | Yes | BGG sync |
| POST | /api/v1/import/csv/preview | Yes | CSV preview |
| POST | /api/v1/import/csv | Yes | CSV import |

## File → Purpose Annotations

- `MBGCApp.swift` — SwiftData ModelContainer init, tab view setup, deep link handling
- `Game.swift` — @Model, all fields from BGG XMLAPI2 shape, `collections: [String]` stored as JSON
- `APIClient.swift` — base URL from env, Authorization header injection, async/await, throws typed errors
- `AuthViewModel.swift` — @Observable, Keychain read/write for Supabase JWT, webview state
- `LibraryViewModel.swift` — @Observable, reads from SwiftData, triggers API sync on pull-to-refresh
- `GameDetailViewModel.swift` — fetches single game, handles collection assignment
- `CSVParser.swift` — pure function: `parseCSV(Data) -> [ImportedGame]` — no network, no dependencies
- `ContentView.swift` — TabView with 4 tabs: Library, Discover, Search, Settings
- `LoginView.swift` — WKWebView loading Supabase hosted UI URL

## Key Patterns

### Observable everywhere
```swift
@Observable class MyViewModel {
  var games: [Game] = []
  var loading = false
}
```
NEVER `ObservableObject`, NEVER `@StateObject`.

### SwiftData reads always, writes queue
```swift
// Read (always from SwiftData first)
var games = try modelContext.fetch(FetchDescriptor<Game>(predicate: #Predicate { $0.isOwned }))

// Write (optimistic local, fire-and-forget API)
game.isOwned = true
try modelContext.save()
Task { try? await apiClient.syncGame(game) }
```

### Auth: Supabase webview
```swift
struct LoginView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: supabaseAuthURL))
        return webView
    }
    // On callback URL with auth token → extract token → store in Keychain
}
```

## Rules — Never Do

- **NEVER modify .pbxproj or .xcodeproj/ contents** — run `xcodegen generate` after changing project.yml
- **NEVER use ObservableObject** — always @Observable
- **NEVER use @StateObject** — always @State with @Observable
- **NEVER use NavigationView** — always NavigationStack
- **NEVER add SPM package without asking first**
- **NEVER change iOS deployment target below 17.0**
- **NEVER store JWT in UserDefaults or localStorage** — use Keychain only

## CSV Import (Pure Local)

```swift
// CSVParser.swift — no network call, no API call
func parseCSV(_ data: Data) -> [ImportedGame] {
    // Expected columns: bgg_id, name, year_published, thumbnail (URL), is_owned, collections
    // Parse with String(data, encoding: .utf8).split(separator: "\r\n")
    // Return [ImportedGame] — agent creates this type from CSV columns
}
```
User opens CSV file via document picker → parsed locally → written to SwiftData → appears in Library immediately.

## Offline Strategy

1. **Login** → fetch full collection → write to SwiftData → done
2. **Read** → always SwiftData first (instant, no spinner)
3. **Mutate** → write SwiftData immediately → fire API call in background Task
4. **CSV import** → pure local, no network ever
5. **BGG sync** → requires login, calls `/import/sync`

## Build & Test (MCP)

```bash
# Use MCP tools — NOT raw xcodebuild
build_sim      # build for simulator
test_sim       # run tests
list_sims      # show available simulators
boot_sim       # boot a simulator

# Fallback (if MCP unavailable):
xcodebuild -scheme MBGC -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

## YAGNI List (Not Building)

- Push notifications
- iPad target
- Watch/tvOS
- Widgets
- Live Activities
- Custom login form (Supabase webview is sufficient)
- Image caching layer (AsyncImage is fine for MVP)
- Offline mutation queue with conflict resolution
- Apollo/GraphQL networking

## Dependency Plan (When Needed)

| Need | Solution |
|------|---------|
| Auth UI | Supabase hosted webview (built-in WKWebView) |
| Keychain | Native Security framework |
| HTTP | Native URLSession async/await |
| Persistence | Native SwiftData |
| CSV parsing | Native Swift string splitting |
| Project generation | XcodeGen (one-time `xcodegen generate`) |
| Build/CLI | XcodeBuildMCP (bunx -y xcodebuildmcp@latest) |
| Agent skills | skills.sh ecosystem |

No third-party dependencies for MVP.

## Pending API Work (Before iOS End-to-End)

| Endpoint | Status | Why iOS Needs It |
|----------|--------|-----------------|
| GET /api/v1/games | Must exist | Collection list |
| GET /api/v1/games/{id} | Must exist | Game detail |
| GET /api/v1/discover | Must exist | Discover tab |
| POST /api/v1/import/sync | Must exist | BGG import |
| POST /api/v1/collections | Nice to have | Create collections |
| GET /api/v1/collections | Nice to have | List collections |

`collection` is 0% done, `game-detail` is 15% done. Build iOS shell + mock data first, then finish API.
