# iOS Backlog — Ranked

Effort: XS (<30min) · S (~1-2hr) · M (half-day) · L (multi-day) · XL (needs research/design first)

## Tier 0 — Bugs (fix regardless of priority)

| # | Item | Effort | Notes |
|---|------|--------|-------|
| 1 | Move/copy after click doesn't close select view | XS | ✅ Done — Copy only cleared `selectedIds`, leaving `isSelecting` true; both actions now call `exitSelection()` (VibesView.swift) |
| 7 | Question w/ 0 options should auto-skip (select all) | S | ✅ Done — `FinderFlow.skipEmptySteps()` auto-appends a "skip" pick and advances when an axis has zero options, instead of stalling on an empty screen or ending the flow early. Regression test: `FinderFlowTests.emptyAxisAutoSkips` |
| 18 | Fix language dependence filter | S | ⏸️ No repro found — `GameFilters.passes()` already does exact-level `Set.contains` matching (not "greater than"), confirmed by new test `GameFiltersTests.languageLevelsMatchExactlyNotGreaterThan`. Reopen with a specific game if wrong results recur after rebuilding. |

## Tier 1 — Quick wins (trivial, ship today)

| # | Item | Effort | Status |
|---|------|--------|--------|
| 6 | "Rename" → "Edit" swipe action text | XS | ✅ Done |
| 10 | Rating filter icon → BGG svg Boardgamegeek-Simple-Icon.svg | XS | ✅ Done — reused existing `bgg-icon` asset (same one GameSort.bggRating uses) |
| 4 | iOS haptics (UIFeedbackGenerator on key actions) | XS | ✅ Done — used `.sensoryFeedback`, not raw `UIFeedbackGenerator` (matches existing ContentView/FinderView pattern). Covers selection toggle, delete, copy/move, collection delete, delete game. |
| 20 | Add-to-collection: move checkbox to right | XS | ✅ Done — both AddGamesSheet (VibesView) and AddToCollectionSheet (GameDetailView) |
| 17 | Game detail view: slight semitransparency | XS | ✅ Done — stats/links boxes now `Color(.systemGray6).opacity(0.7)` |
| 22 | Ellipsis menu: share/copy BGG link | S | ✅ Done |
| 5 | Reorder filters, custom most-important-first | S | ✅ Done — unified BGG-familiar order across all filter types (was numeric-only before): Type, Categories, Mechanics, Players, Playtime, Complexity, Best For, Rating, BGG Rank, My Rating, Language, Designers, Artists, Publisher, Year, Times Played, Title. `FilterRowKind` in FilterView.swift drives the single ordered list. |
| 15 | Background gradient colors | S | ⏸️ Skipped — FinderView/FinderStartView bg was deliberately flattened from a gradient to flat #F5F5F5 on Jun 29 as part of design-token cleanup. Re-adding contradicts that decision; needs a concrete spec before touching. |
| 21 | Collection icon corner badge (smart vs ranked) | S | ✅ Done — purple bolt for smart, pink star for ranked |
| 27 | Clean up import log (no blank lines, iOS feel) | S | ✅ Done — guards against blank/whitespace log lines, per-status icons (check/warning/x) instead of uniform dot, capped in a 160pt scroll view so a large import doesn't blow out the layout |

## Tier 2 — Main goal + direct enablers

| # | Item | Effort |
|---|------|--------|
| 3 | **Search games by filters (stated main goal)** | L |
| 11 | Add filter to search view — simpler, own UI (not reused FilterView) | M |
| 2 | Search inside a collection (ref: overboard-collections.PNG) | S–M |
| 30 | Recent search results in search view | S–M |
| 13 | Clickable game attributes → auto temp filter/collection | L — build after #3, reuses its filter engine |

## Tier 3 — Medium features

| # | Item | Effort |
|---|------|--------|
| 8 | Add "type of game" question to Finder | M |
| 19 | Guided first-run tour | M — OnboardingView.swift already exists, extend it |
| 29 | Alphabet scroll index (Contacts-style) | M |
| 28 | More colors/icons for collection customization | S–M |
| 14 | Improve collection grid view | M — needs a concrete spec, currently vague |
| 12 | Game detail view → swipe-up sheet presentation | M–L — navigation architecture change |
| 23 | Rules section on game detail | M — new data model field |
| 25 | Custom markdown rules input (char-limited) | S–M — depends on #23 |
| 24 | Upload PDF/txt/md for rules | M–L — depends on #23, needs file storage decision |
| 16 | Game detail: blend image into background | S–M |
| 33 | Settings row to let user drag-reorder filters themselves | M — replaces hardcoded `FilterRowKind.rowOrder` (FilterView.swift) with a persisted user preference; needs a drag-to-reorder list UI + fallback to default order |

## Tier 4 — Big bets / needs a decision first (Confusion Protocol)

| # | Item | Effort | Why it's not a quick yes |
|---|------|--------|--------------------------|
| 26 | Liquid Glass UI effect | M–L | iOS 26-only API — raises min deployment target, check current target first |
| 31 | Manual game add via photo scan | XL | needs OCR/vision + BGG title matching, real R&D |
| 32 | Add game via barcode scan | XL | BGG has no public barcode DB — feasibility unproven, spike before committing |
| 9 | Move ios/ to its own repo | L | git history split, CI/docs/media references all need updating — ask first per AGENTS.md scope rules |

## Suggested order

1. Fix the 3 bugs (#1, #7, #18) — cheap, they're actively annoying.
2. Clear the Tier 1 quick-win list in one sitting — ~10 items, all XS/S, high visible polish per minute spent.
3. Build #3 (search by filters) — it's the named main goal; #2, #11, #13, #30 hang off it, so sequencing them after avoids rework.
4. Tier 3 as capacity allows, own timelines.
5. Tier 4 — don't start without answering the open question in each row first (barcode feasibility, repo split scope, min iOS version for Liquid Glass).
