# iOS Backlog — Ranked

Effort: XS (<30min) · S (~1-2hr) · M (half-day) · L (multi-day) · XL (needs research/design first)

## Tier 2 — Main goal + direct enablers

| # | Item | Effort |
|---|------|--------|
| 3 | **Search games by filters (stated main goal)** | L |
| 11 | Add filter to search view — simpler, own UI (not reused FilterView) | M |
| 30 | Recent search results in search view | S–M |
| 13 | Clickable game attributes → auto temp filter/collection | L — build after #3, reuses its filter engine |

## Tier 3 — Medium features

| # | Item | Effort |
|---|------|--------|
| 8 | Add "type of game" question to Finder | M |
| 19 | Guided first-run tour | M — OnboardingView.swift already exists, extend it |
| 29 | Alphabet scroll index (Contacts-style) | M |
| 28 | More colors/icons for collection customization | S–M |
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

## Future ideas (unsorted)

1. Make algorithm for "best" game in finder result, configurable by user (e.g., weighted sum of rating, playtime, complexity, etc.), enable or disable which attributes to include in the score. (M–L)
2. Make a singular unified DB for all games, so information is not lost between different collections. (XL)
3. Include all games of all time in DB, use datadump folder as start point.
4. Change finder tiles / buttons colors. 