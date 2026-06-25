# iOS Design & Layout — MBGC (Overboard-style)

UX reference: **Overboard.app**. Source screenshots in `overboard-media-examples-screenshoots/`.
Companion to [`ios-plan.md`](./ios-plan.md) (stack/architecture). This doc = screens, flows, components.
Goal for now: **functional parity with Overboard's layout, not pixel-perfect polish.**

---

## App map (high level)

```
Launch
 └─ LoginView (if no token)
      └─ RootTabBar (floating pill, bottom)
           ├─ Discover  (browse / search BGG)
           ├─ Collection  ◀ default tab
           │    ├─ Collection list (Library / Wishlist / Shared / Smart Lists)
           │    │    └─ Game grid  (tap row)
           │    │         └─ GameDetailView (hero → details → log play → quick thoughts)
           │    ├─ [+] FAB → Create Smart List sheet
           │    │              └─ Set Filters sheet
           │    └─ Settings (gear, top-right)
           └─ Search (magnifier, bottom-right standalone button)
```

Two persistent chrome elements float over content (not a standard `TabView` bar):
- **Bottom-left pill:** Discover ⇄ Collection toggle.
- **Bottom-right circle:** Search.
- **Bottom-right square (Collection tab only):** orange `+` FAB.

> SwiftUI note: this is a custom overlay bar, not `TabView`. Implement as a `ZStack` with content + a bottom `HStack` of capsule buttons. See `ios-plan.md` ContentView.

---

## Navigation flow (verbs)

```
Collection row     ──tap──▶  Game grid for that list
Collection "•••"   ──tap──▶  Share/Options sheet ──Copy Link / Stop Sharing
Game grid cell     ──tap──▶  GameDetailView (sheet, full-screen cover)
GameDetail X       ──tap──▶  dismiss to grid
GameDetail "Add to…" ─tap──▶  Add-to-collection bottom sheet (toggle rows, no confirm step)
GameDetail calendar+ ─tap──▶  Log play → Quick thoughts flow (rating → themed Q&A cards → Save)
[+] FAB            ──tap──▶  Create Smart List (modal sheet)
Set Filters        ──tap──▶  Filters (nested sheet) ──Done──▶ back to Create
gear               ──tap──▶  Settings (Done → dismiss)
Discover/Search    ──tap──▶  swap root content
```

---

## Screens (extracted from shared screenshots)

### 1. Collection home — `overboard-collections.PNG`
- **Header:** large bold title "Collection". Gear button top-right (orange glyph in white circle).
- **List rows** (icon + title + optional subtitle + right-aligned count):
  | icon | title | subtitle | count |
  |---|---|---|---|
  | blue 4-square grid | Library | — | 1 |
  | pink double-heart | Wishlist | — | 0 |
  | orange 4-square grid | Library | Shared | 115 |
- Row = colored rounded-square icon (left) · title (semibold) · count (right, large).
- **Chrome:** orange `+` FAB (bottom-right square), floating Discover/Collection pill (bottom-left), search circle (bottom-right).
- Background: warm cream (`#FBF7E9`-ish). Title text: dark brown.

### 2. Create Smart List — `overboard-create-collection.PNG`
- Modal sheet. **Cancel** (left), title "Smart List", **Create** (right, disabled until valid).
- Editable icon preview (rounded square, tinted by selected color) centered up top.
- "Name" large placeholder (tappable text field).
- **Set Filters** button: full-width pill, tinted to selected color, filter-sliders glyph left, active-filter count badge right (`0`).
- **Color picker:** 5×3 grid of color swatches; selection = ring outline.
- **Icon picker:** scrollable grid of glyphs (list, meeple, crown, lightning, star, smiley, frown, robot, flag, sun, moon, comet, thumbs-up, thumbs-down, heart, ghost, award, badge, bookmark, check…); selection = ring outline.
- Whole sheet recolors live to the chosen accent color.

### 3. Filters — `overboard-filters-example-selected.PNG`
- Sheet. Title "Filters", **Done** (top-right).
- **"Enabled filters"** section — active filter cards, each: icon · label · mode dropdown (Minimum / Maximum / Exactly) · control · current value.
  - **My Rating** — star icon — Minimum — slider — `5`
  - **Rank** — badge icon — Exactly — big numeric display — `100`
  - **Playtime** — clock icon — Maximum — slider — `60 minutes`
- **"Other filters"** section — inactive list rows, each with right-side mode dropdown defaulting to **Off**: Lists, Rating, Published, Players, Last Played…
- Each filter has its own accent color (rating=orange, rank=yellow, playtime=green).
- Pattern: tapping an "Other" row's dropdown off→on promotes it into "Enabled filters".

### 4. Game detail — hero — `overboard-game-profile-1.PNG`
- Full-screen cover. **X** close (top-left), **AR/3D cube** icon (top-right).
- Hero artwork fills top third; designer name small-caps above title overlay.
- Game **title** large below art.
- **Meta row:** year `2024` · `+` quick-add · `BGG 8.0` badge · `10+` age badge.
- **Stats card** (3 columns): PLAYERS `1-4` (Best: 2) · PLAYTIME `30-45` Minutes · WEIGHT `2.0` Complexity.
- **Description** paragraph with "More.." expander.
- **Bottom action bar** (floating, 3 buttons): `+` hexagon (add) · "Add to… `N`" center pill · calendar-plus (log play).

### 5. Game detail — details (scrolled) — `overboard-game-profile-2.PNG`
- Header collapses to centered title "Harmonies" with X + cube.
- **Game Details** heading.
- **Type** — pill chips w/ icon: Abstract Games, Family Games.
- **Categories** — chips: Abstract Strategy, Animals, Environmental, Puzzle.
- **Mechanics** — chips: Chaining, Hexagon Grid, Open Drafting, Pattern Building, Set Collection, Solo/Solitaire, Tile Placement, Variable Player Powers.
- "POWERED BY BGG" footer. Same bottom action bar persists.

### 6. App Settings — *(pasted, no saved file — name TBD, e.g. `overboard-settings.PNG`)*
- Sheet, dark mode. Title "Settings" centered, **Done** (top-right, orange text in dark pill).
- **Group 1 (preferences):**
  - Appearance → chevron (light/dark/system picker)
  - Haptics → toggle (orange, on)
  - Open links in → dropdown, "System Browser"
  - Open app on → dropdown, "Collection" (sets default launch tab)
- **Group 2 (community/monetization):**
  - Rate the App → external-link arrow
  - Buy Merch → external-link arrow
  - Donate → chevron
- **Group 3 (data):**
  - Import from BGG → "•••" overflow menu
- **Group 4 (meta):**
  - Help & Support → chevron
  - About → chevron
- Each row: colored rounded-square icon (left), label, trailing control. Rows grouped into separate rounded-rect cards with spacing between groups (iOS `Form`/`List` insetGrouped style maps directly).

### 7. Add to collection — `overboard-add-game-to-collection.PNG`
- Bottom sheet overlay on top of GameDetailView (dimmed background, hero still visible behind).
- Title "Add to…" centered.
- Row per collection: icon tile · name · trailing control —
  - Library → empty square `+` (not added)
  - Wishlist → empty square `+` (not added)
  - Library (Shared, orange tile, row highlighted) → filled orange checkbox ✓ (added)
- Tapping a row toggles add/remove in place — no separate confirm step.

### 8. Quick thoughts — rating + theme — `overboard-game-profile-quick-thoughts-1.PNG`
- Full-screen cover, olive-green themed (per-game accent from box art?). **Cancel** (top-left) · list/outline icon (top-center, toggles structured-question view) · **Save** (top-right).
- **Score hexagon:** big number `7.5`, qualitative label below ("Great"), ringed hexagon outline.
- **1–10 scale strip:** horizontal dot track, numbered ticks 1/2/3/4/5/6/9/10 (7/8 hidden under the selected thumb), draggable circular thumb.
- **Quick-thoughts Q&A cards** start below, each: bold question, grey helper subtext, then a row of 3 square option cards (emoji + label):
  - "How strong is the theme?" → Barely there 😶 / It's there 👍 / Immersive 🤓

### 9. Quick thoughts — vibe + complexity (scrolled) — `overboard-game-profile-quick-thoughts-2.PNG`
- Same screen, scrolled further. Same Cancel/list/Save header persists (sticky).
- "How does it look on the table?" → Not my style 😐 / Nice 😉 / Gorgeous 😍
- "What's the overall vibe?" → Chill 😌 / Focused 🎯 / Intense 🔥
- "How complex does this game feel?" → Light 😊 / Medium 🧐 / Heavy 🧠
- Pattern: every quick-thoughts question = 3-up emoji card grid, single-select, consistent card size. Likely 4–6 questions total scrolling (only 2 of 4 quick-thoughts screenshots scanned so far — see tracker).

### 10. Collection share/options — `overboard-share-collection.PNG`
- Sheet (light), reached from a collection's "•••" options menu. Orange checkmark (top-right, confirms/closes).
- Centered icon tile (large, the collection's own icon/color) + collection name "Library" as heading.
- **Owner row:** avatar placeholder + "(Owner)" + chevron (tap → manage/transfer ownership or view member).
- **Share Options** row: title + helper text "Anyone with the link can make changes." + chevron (→ permission level picker, e.g. view vs. edit).
- **Copy Link** row: label + document/copy icon.
- **Stop Sharing**: full-width destructive button (red text), unbundles the collection back to private.

---

## Component inventory (reusable SwiftUI views to build)

| Component | Used in | Notes |
|---|---|---|
| `CollectionRow` | home | icon tile + title + subtitle + count |
| `IconTile` | rows, smart-list preview | colored rounded square + glyph |
| `FloatingTabBar` | all root screens | custom overlay, not TabView |
| `AccentColorPicker` | create smart list | 5×3 swatch grid, ring selection |
| `GlyphPicker` | create smart list | scroll grid, ring selection |
| `FilterCard` | filters | icon + label + mode menu + slider/stepper + value |
| `FilterModeMenu` | filters | Min / Max / Exactly / Off |
| `StatColumn` | game detail | label + value + unit |
| `Chip` | game detail | tag pill, optional leading icon |
| `GameActionBar` | game detail | 3-button floating bar |
| `BadgePill` | game detail | BGG score, age |

---

## Design tokens (eyeballed — refine later)

- Background cream: `#FBF7E9`
- Primary text: dark brown `#3A2A22`
- Accent orange (brand): `#F2580C`-ish
- Per-feature accents: rating=orange, rank=yellow, playtime=green, smart-list=user-chosen
- Corner radius: ~16–20 on cards/tiles, ~12 on chips, full-capsule on action pills
- Floating chrome: heavy shadow, translucent white circles/capsules

> These are guesses from screenshots. Lock real values when building, or sample with a color picker.

---

## Image scan tracker

Scanned once into this doc → don't re-upload. Pending = share later, one batch.

### ✅ Scanned (in this doc)
- `overboard-collections.PNG` → §1
- `overboard-create-collection.PNG` → §2
- `overboard-filters-example-selected.PNG` → §3
- `overboard-game-profile-1.PNG` → §4
- `overboard-game-profile-2.PNG` → §5
- App Settings (pasted only, not saved to folder — file name unknown) → §6
- `overboard-add-game-to-collection.PNG` → §7
- `overboard-game-profile-quick-thoughts-1.PNG` → §8
- `overboard-game-profile-quick-thoughts-2.PNG` → §9
- `overboard-share-collection.PNG` → §10

### ⏳ Pending (not yet scanned)
- `overboard-all-filters-no-selected.PNG`
- `overboard-all-filters-no-selected-2.PNG`
- `overboard-collection-options.PNG`
- `overboard-create-collection-types.PNG`
- `overboard-create-collection-with-filters.PNG`
- `overboard-game-profile-3.PNG`
- `overboard-game-profile-4.PNG`
- `overboard-game-profile-5.PNG`
- `overboard-game-profile-log-play.PNG`
- `overboard-game-profile-quick-thoughts-3.PNG`
- `overboard-game-profile-quick-thoughts-4.PNG`
- `overboard-regular-collection-example.PNG`
- `overboard-select-game-example.PNG`
- `overboard-sort-collection.PNG`
- `overboard-sorted-collection-example.PNG`

### 🎬 Video (not scannable as image)
- `overboard-game-profile-video-scroll-select.mov` — describe verbally or share key frames as PNG.
