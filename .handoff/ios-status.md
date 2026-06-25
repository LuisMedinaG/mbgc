# iOS App Status — MBGC [SUPERSEDED]

> **This file is stale as of 2026-06-25.** The iOS app was migrated to a local-first
> architecture — no login, no backend calls. See:
> - `docs/handoff/2026-06-25-ios-local-first.md` — full change log (Sessions 1–3)
> - `ios/AGENTS.md` — current architecture, data model, what works, what's dead code
>
> Everything below describes the pre-migration state and is kept for historical reference only.

---

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
- All bug ledger items (see below).

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

## Bug ledger (all fixed)

| Bug | Fix |
|-----|-----|
| Library refresh deleted local games beyond API page 1 | `listGames` now walks all pages before diffing |
| Search query string could inject `&`/`=`/`#` into URL | Built via `URLComponents` |
| Logout left prior account's games in SwiftData | Cleared via `onChange` in `MBGCApp` |
| `SearchView` collapsed network errors into false "no results" | `do/catch` + `errorMessage` state |
| `MBGCTests` target couldn't build | Added `GENERATE_INFOPLIST_FILE: YES` |
| `GameDTO`/`GameDetailDTO` were 4x copy-pasted | Collapsed to one DTO + `typealias` |
| Sparse game fields crashed decoding | Made optional with `decodeIfPresent` |
| `langDep[game.languageDependence]` out-of-bounds | Now bounds-checked |
| CSV import broken end-to-end | Fixed DTO shapes to match real API contract |

## YAGNI (not building)

Push notifications, iPad/Watch/tvOS, widgets, Live Activities, offline mutation queue with
conflict resolution, Apollo/GraphQL, image-caching library (native `URLCache` tuned instead).
