# Home Layout & Navigation Flow

Replicates the Overboard "Collection" screen. Replaces the 4-tab `TabView` in
`ContentView` with a single `ZStack` (content) + floating overlay controls.

## Screen anatomy

```
┌─────────────────────────────┐
│ 7:03                  ( ⚙ )  │  ← gear, top-right, floating circle
│                             │
│  Collection                 │  ← large title
│                             │
│  ▦  Library            1    │  ← collection rows: icon · name · count
│  ♥  Wishlist           0    │     (optional gray subtitle, e.g. "Shared")
│  ▦  Library                 │
│     Shared           115    │
│                             │
│                             │
│                      ( + )  │  ← orange add button (floating)
│  ( Discover | Collection )  ← pill, bottom-LEFT (joined segments)
│                      ( 🔍 ) │  ← search button (floating), BELOW the +
└─────────────────────────────┘
```

Layout note: `+` sits **above** `🔍` (both bottom-right). Pill is bottom-left,
vertically aligned with the search button row.

## Components

| Element | Maps to | Notes |
|---|---|---|
| Content area | `VibesView` (Collection) / Discover feed | swapped by pill |
| `Discover\|Collection` pill | new `HomePillView` | 2 joined segments, active=orange |
| `+` floating button | "New Collection" action | orange filled circle |
| `🔍` floating button | `SearchView` | white circle, gray glass icon |
| `⚙` gear, top-right | `SettingsView` | white circle, orange icon |
| Collection row | `VibesView` list row | leading icon, trailing count |

## State

`ContentView` owns:
- `@State var tab: HomeTab = .collection`  (`.discover` / `.collection`)
- `@State var showSearch = false`  → `.sheet { SearchView() }`
- `@State var showSettings = false` → `.sheet { SettingsView() }`
- `@State var showNewCollection = false` → `.sheet { /* new collection form */ }`

## Flow

```
Home
 ├─ pill → Discover      : swaps content to Discover feed
 ├─ pill → Collection    : swaps content to collections list (default)
 ├─ ⚙  gear              : SHEET → Settings
 ├─ 🔍 search            : SHEET → Search
 ├─ +  add               : SHEET → New Collection form
 └─ tap collection row   : PUSH → collection detail (game list)
```

- Pill = swap content in place (no navigation).
- `+`, `🔍`, `⚙` = modal sheets (dismiss returns home).
- Collection row = push (back button returns home).

## Collections shown

Driven by API (`useCollections`/`VibesViewModel`). One default collection
**"Library"** always present. Others (Wishlist, shared) appear as the user
creates/joins them.

## Layout skeleton

```swift
ZStack {
    Group {
        switch tab {
        case .collection: CollectionListView()   // VibesView content
        case .discover:   DiscoverView()
        }
    }

    // top-right gear
    VStack { HStack { Spacer(); gearButton } ; Spacer() }
        .padding()

    // bottom overlay
    VStack {
        Spacer()
        HStack(alignment: .bottom) {
            HomePillView(tab: $tab)        // bottom-left
            Spacer()
            VStack(spacing: 12) {          // bottom-right stack
                addButton                  // +
                searchButton               // 🔍
            }
        }
        .padding()
    }
}
```
