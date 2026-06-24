# iOS App Plan — MBGC (My Board Game Collection)

## Context

iOS native frontend for MBGC backend. Overboard.app as UX reference.
Same repo as Go API + React web (`mbgc/` monorepo).

## Stack

- SwiftUI + SwiftData + URLSession (no Apollo, no Combine, no third-party networking)
- Swift 6.2 / iOS 17+ deployment target
- XcodeGen for project generation
- Bun for npm package management
- Auth: native SwiftUI login form → Go API `POST /api/v1/auth/login` (mirrors web; no Supabase webview/SDK)
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
│   │   └── AuthViewModel.swift # @Observable — login form, access+refresh tokens, refresh flow
│   │   └── LibraryViewModel.swift
│   │   └── GameDetailViewModel.swift
│   ├── Views/
│   │   ├── ContentView.swift   # TabView: Library, Search, Settings (3 tabs)
│   │   ├── LibraryView.swift   # Grid of owned games from SwiftData, pull-to-refresh
│   │   ├── SearchView.swift    # /api/v1/games?q=
│   │   ├── GameDetailView.swift
│   │   ├── ImportView.swift    # BGG username input → sync
│   │   ├── CSVImportView.swift # upload → /import/csv/preview → select → /import/csv (server round-trip)
│   │   ├── SettingsView.swift  # BGG username, logout
│   │   └── LoginView.swift     # native email/password form → POST /api/v1/auth/login
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
| POST | /api/v1/auth/login | No | Login → access+refresh tokens |
| POST | /api/v1/auth/refresh | No | Refresh expired access token |
| POST | /api/v1/import/sync | Yes | BGG sync |
| POST | /api/v1/import/csv/preview | Yes | CSV preview (multipart upload → `{bgg_id, name}` rows) |
| POST | /api/v1/import/csv | Yes | CSV import (`{bgg_ids: [int]}`, max 100, server enriches via BGG) |

> All responses wrapped: single `{ "data": T }`, list `{ "data": [T], "meta": {page,limit,total} }`,
> error `{ "error": {code,message,details} }`. Backend emits **snake_case** — decode with
> `.convertFromSnakeCase`. `GET /api/v1/discover` exists but **requires `?collection_id=`**
> (similar-to-a-collection, not popular games) — no Discover tab in MVP.

## File → Purpose Annotations

- `MBGCApp.swift` — SwiftData ModelContainer init, tab view setup, deep link handling
- `Game.swift` — @Model, fields from BGG XMLAPI2 shape; most are **optional** (nullable in API); `vibes: [{id, name}]` for collections
- `APIClient.swift` — base URL from env, Bearer header injection, decodes `Response<T>`/`ListResponse<T>` envelopes, `.convertFromSnakeCase`, throws typed errors
- `AuthViewModel.swift` — @Observable, native login form; Keychain read/write for access+refresh tokens; refresh-on-401 flow
- `LibraryViewModel.swift` — @Observable, reads from SwiftData, triggers API sync on pull-to-refresh
- `GameDetailViewModel.swift` — fetches single game, handles collection assignment
- `ContentView.swift` — TabView with 3 tabs: Library, Search, Settings
- `LoginView.swift` — native SwiftUI email/password form → `POST /api/v1/auth/login`

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

### Auth: native form → Go API (mirrors web app)
```swift
// No Supabase webview/SDK. POST credentials to the Go API, store both tokens in Keychain.
struct LoginRequest: Codable { let username: String; let password: String }
struct LoginResponse: Codable { let access_token: String; let refresh_token: String; let expires_in: Int }

let res: Response<LoginResponse> = try await apiClient.post("/api/v1/auth/login",
    body: LoginRequest(username: email, password: password))
Keychain.set(res.data.access_token, .access)
Keychain.set(res.data.refresh_token, .refresh)

// On 401: POST /api/v1/auth/refresh { refresh_token } → new tokens → retry once.
// Auth endpoints rate-limited 5 req/s → show friendly retry on 429.
```

## Rules — Never Do

- **NEVER modify .pbxproj or .xcodeproj/ contents** — run `xcodegen generate` after changing project.yml
- **NEVER use ObservableObject** — always @Observable
- **NEVER use @StateObject** — always @State with @Observable
- **NEVER use NavigationView** — always NavigationStack
- **NEVER add SPM package without asking first**
- **NEVER change iOS deployment target below 17.0**
- **NEVER store JWT in UserDefaults or localStorage** — use Keychain only

## CSV Import (Server Round-Trip)

The CSV only carries `bgg_id`+`name`; the server enriches each id from BGG, so import is online-only.

```
1. Document picker → pick CSV file
2. Multipart POST file to /api/v1/import/csv/preview → returns [{bgg_id, name}] rows
3. User selects rows to import (UI list with checkboxes)
4. POST /api/v1/import/csv { bgg_ids: [int] }  (max 100) → server fetches full data from BGG
5. Response { imported, skipped, failed } → refetch /api/v1/games → SwiftData
```
No local CSV parser, no local-only write — full game metadata (thumbnail, year, etc.) comes from the server.

## Offline Strategy

1. **Login** → native form → `/auth/login` → tokens to Keychain → fetch full collection → write to SwiftData → done
2. **Read** → always SwiftData first (instant, no spinner)
3. **Mutate** → write SwiftData immediately → fire API call in background Task
4. **CSV import** → online-only: upload → preview → select → `/import/csv` (server enriches via BGG)
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
- Discover tab (API requires collection_id; revisit when a popular-games endpoint exists)
- Image caching layer (AsyncImage is fine for MVP)
- Offline mutation queue with conflict resolution
- Apollo/GraphQL networking

## Dependency Plan (When Needed)

| Need | Solution |
|------|---------|
| Auth UI | Native SwiftUI form → `POST /api/v1/auth/login` (no webview, no Supabase SDK) |
| Keychain | Native Security framework |
| HTTP | Native URLSession async/await |
| Persistence | Native SwiftData |
| CSV parsing | Native Swift string splitting |
| Project generation | XcodeGen (one-time `xcodegen generate`) |
| Build/CLI | XcodeBuildMCP (bunx -y xcodebuildmcp@latest) |
| Agent skills | skills.sh ecosystem |

No third-party dependencies for MVP.

## API Status

All 13 endpoints exist and work today (verified in `services/api/internal/catalog/handler.go`
and `services/api/internal/importer/handler.go`). Build iOS against the **real** API — no API work
is blocking. Mock data is optional, for offline UI iteration only, not a prerequisite.
