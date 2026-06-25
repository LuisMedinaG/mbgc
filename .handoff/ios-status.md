# iOS App Status — MBGC

Supersedes `ios-plan.md`, `ios-improvement-plan.md`, `ios-design.md` (deleted — they had
drifted from each other and from the implementation; this is the single source of truth).

## Stack & architecture (unchanged, working)

SwiftUI + SwiftData + URLSession, Swift 6.2 / iOS 17+, XcodeGen, zero third-party deps.
`@Observable` everywhere (never `ObservableObject`/`@StateObject`), `NavigationStack`,
Keychain-only token storage, `actor APIClient` with single-flight token refresh.

```
ios/MBGC/
├── MBGCApp.swift           App entry, ModelContainer, clears SwiftData on logout
├── Models/Game.swift       @Model + GameDTO (shared by list & detail responses)
├── Networking/APIClient.swift
├── ViewModels/             Auth, Library, GameDetail, Import, Profile
└── Views/                  ContentView (3-tab), Library, Search, GameDetail,
                             Import, CsvImport, Profile, Settings, Login
```

## Design direction: native, not a UI clone

**Decision:** ship with stock SwiftUI components (`List`, `Form`, `TabView`) styled with the
system look. The earlier `ios-design.md` spec'd a full Overboard.app visual clone (floating
pill tab bar, FAB, smart-list filter sheets, quick-thoughts rating flow, custom color tokens).
That's a multi-week design project, not a polish pass — deferred indefinitely. Revisit only if
explicitly requested.

## What's done

- Login, Library (list, pull-to-refresh, cache-first), Search, Game Detail (hero, stats,
  tags, vibes editing, rules link, delete), Profile, BGG sync import, CSV import
  (preview → import).
- Offline-first reads: Library and Game Detail render from SwiftData instantly, then
  refresh from the API in the background.

## Speed (done this pass)

- `GameDetailViewModel.load` renders the cached `Game` row first (instant), then
  overwrites with the network fetch — no more spinner on revisit.
- `URLCache.shared` tuned to 50MB memory / 200MB disk in `MBGCApp.init()` —
  `AsyncImage` rides `URLSession.shared`, so thumbnails/hero images now persist
  across launches instead of re-downloading every cold start.

- `LibraryViewModel.refresh` now reports `loadProgress` (loaded/total) per page via
  `APIClient.listGames(onPage:)`; `LibraryView` shows "Loading X of Y…" instead of a bare
  spinner once the library spans more than one page.

Deferred (too big for this pass, see `docs/ios-api-needs.md` for the backend half):
- Lite list payload, async BGG sync job, incremental sync — all need a Go API change first.

## What's pending

**Vibes/Collections (Phase 5, partial):** game-detail vibe *assignment* exists
(`GameDetailViewModel.saveVibes`); collection *management* does not — no dedicated tab, no
create/rename/delete UI, no `GET /discover?collection_id=` browse. Build when needed.

## Bug ledger

Fixed in this pass:
- Library refresh deleted local games beyond API page 1 (`listGames` now walks all pages).
- Search query string could inject `&`/`=`/`#` into the URL (now built via `URLComponents`).
- Logout left the prior account's games in SwiftData (now cleared via `onChange` in
  `MBGCApp`).
- `SearchView` collapsed network errors into a false "no results" empty state.
- `MBGCTests` target couldn't build (missing `GENERATE_INFOPLIST_FILE`) — tests now run.
- `GameDTO`/`GameDetailDTO` were duplicate 20-field structs with 4x copy-pasted field
  mapping — collapsed to one DTO + `typealias`.
- `description`/`weight`/`rating`/`languageDependence` were declared non-optional in the
  DTO while the API omits them when null — decoding crashed on any sparse game. Now
  optional with explicit `decodeIfPresent`.
- `langDep[game.languageDependence]` could index out of bounds — now bounds-checked.
- **CSV import was broken end-to-end**: `CSVPreviewResult`/`CSVPreviewRow.alreadyOwned`/
  `CSVImportResult` didn't match the real API shapes (`{data, meta}` envelopes, no
  `already_owned` field, `SyncResult{imported, skipped, failed[]}` not
  `{imported, failed: Int}`). Every CSV preview/import call would have failed to decode.
  Fixed by reusing the actual contract; server already skips owned games server-side.

## YAGNI (not building)

Push notifications, iPad/Watch/tvOS, widgets, Live Activities, offline mutation queue with
conflict resolution, Apollo/GraphQL, image-caching library (native `URLCache` tuned instead).
