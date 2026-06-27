# Game Night Finder — Design Doc

_Status: proposed · 2026-06-26 · target: iOS (local-first)_

## 1. The pitch

Find a game for the occasion with **no typing and no menus** — just big,
full-screen buttons. Start from a vibe, then each tap narrows your **owned**
games by one question, and the app only ever offers choices that still have
games behind them. When the field is small enough, it reveals a top 3.

Think **Akinator for game night**, run entirely on the phone that's already on
the table.

## 2. Why this is small (it builds on what exists)

This is **not** a new search engine. It's a progressive-narrowing UI on top of
data and concepts the app already has:

| Already in the repo | Reused as |
| --- | --- |
| `Collection` (SwiftData, user-created: "party", "euro", "cutthroat") | The **vibe** — the funnel's root node |
| `Game` fields: `minPlayers` / `maxPlayers` / `recommendedPlayers` (BGG best-at poll), `playtime`, `weight`, `rating`, `languageDependence`, `categories`, `mechanics` | The **filter axes** — a known, finite pool of questions |
| Library default collection = owned games | The candidate set v1 narrows |

Net new code is one flow model + three full-screen views + a result view. No
backend (the iOS app is local-first; this stays on-device over SwiftData).

## 3. Decisions locked

| Decision | Choice | Note |
| --- | --- | --- |
| Platform | **iOS first** | Local-first = instant, offline filtering at the table. Web can follow later. |
| Vibe source | **Existing `Collection`s** | Root node = pick a collection. Zero new data model. |
| v1 scope | **Fixed funnel**, structured to become configurable | Hard-code 3 questions now; model them so reordering/toggling is a later settings screen, not a rewrite. |
| Ranking | **Layered tiebreakers** | own rating → avg BGG rating → player-count fit. Configurable later. |

## 4. The funnel (v1 — fixed order)

```
[ Vibe ]      pick a Collection            ← big buttons, one per collection
   │
   ▼
[ Players tonight ]   only counts with games behind them
   │
   ▼
[ Duration ]   only buckets with games behind them
   │
   ▼
[ Reveal ]    #1 pick, then #2, #3   ·   "See all N matches"
```

**Early-stop rule (this is what makes it feel like Akinator, not a form):** after
any pick, if the surviving set is ≤ 3 games — or the next axis can't split the
set (every survivor shares one value) — skip remaining questions and go straight
to the reveal. The funnel length is a *ceiling*, not a fixed count.

## 5. The core mechanic — "only offer choices with games behind them"

After each selection, recompute over the surviving `[Game]`:

1. **Filter** survivors by the chosen value.
2. **Derive** the *next* axis's options from what survives — render only those.

Per axis:

| Axis | Option derived when… | Filter keeps a game when… |
| --- | --- | --- |
| **Vibe** | the collection is non-empty | game ∈ collection |
| **Players (N)** | ∃ survivor with `minPlayers ≤ N ≤ maxPlayers` (N spans `min(minPlayers)…max(maxPlayers)`, capped, e.g. 1–8 then "8+") | `minPlayers ≤ N ≤ maxPlayers` |
| **Duration** | the bucket has ≥1 survivor | game's `playtime` falls in bucket |

Duration buckets (only shown if non-empty): **Quick** `<30` · **Short** `30–60` ·
**Medium** `60–120` · **Long** `120+`. Games with no `playtime` go in an
"Any length" bucket so they're never silently dropped.

Because options are derived from survivors, a dead-end (0 games) is structurally
impossible — but guard for it anyway (e.g. a game missing both player fields).

## 6. Ranking — the reveal order

Sort survivors by a comparator chain (first non-tie wins):

1. **Own rating** desc — your personal BGG rating, `nil` sorts last. _(needs a new field — see §7)_
2. **BGG average rating** (`rating`) desc — `nil` last.
3. **Player-count fit** — `chosenN ∈ recommendedPlayers` (BGG "best at" poll) sorts first.

Show top 3; everything else lives behind **"See all N matches"**. A **re-roll**
button on the result screen is cheap and worth it for indecisive groups.

The chain is data, not branching code — an ordered list of comparators — so the
"configure your tiebreakers later" goal is just persisting a different order.

## 7. Data: what's there vs. what's missing

- **Present:** every axis in §5/§6 reads an existing `Game` field — except one.
- **Missing — `userRating: Double?`** (your personal rating). The current
  `rating` field is the BGG *community average* only (parsed from
  `<ratings><average>` in `BGGXMLParser`). Your #1 tiebreaker wants *your* score.

  - Source: BGG **collection** endpoint (`<rating value="N">` per item) or the CSV
    import's rating column — not the `thing` endpoint already used.
  - **v1 ships without it:** if `userRating` is `nil` everywhere, ranking falls
    through to avg rating → player fit. Capturing it is a thin near-future
    follow-up, not a blocker. _(ponytail: don't gate the funnel on a data-capture task.)_

## 8. Architecture (iOS, local-first)

Pure on-device. No new networking. Three pieces:

**(a) `FinderAxis` — the configurability "base" the funnel rides on.**
A single enum where each case knows how to derive its own options and filter the
survivors. This is the *minimal* shape that makes the funnel reorderable later —
no protocol hierarchy, no DI, no factory.

```swift
enum FinderAxis: Codable {            // Codable → a saved config is just [FinderAxis]
    case vibe, players, duration
    // later: weight, language, category, mechanic — drop-in, no new plumbing

    func options(from games: [Game], context: FinderContext) -> [FinderOption]
    func filter(_ games: [Game], by option: FinderOption) -> [Game]
}

let v1Funnel: [FinderAxis] = [.vibe, .players, .duration]   // ← the only hard-coded part
```

**(b) `FinderFlow` — an `@Observable` holding funnel state** (the ordered axes, the
picks so far). `survivors` and `nextOptions` are **pure functions** of
`(allOwnedGames, picks)` — trivially testable, no side effects. Early-stop and
ranking live here.

**(c) Views** — full-screen, button-only:
- `FinderStepView` — one question, options as screen-filling buttons + a subtle
  "N games left" + a back affordance (un-narrows one step).
- `FinderResultView` — #1 hero, #2/#3 below, "See all", re-roll.

Entry point: a prominent button or a new tab (working name **"Tonight"** —
"Vibes"/"Collection" is taken). Naming is open.

## 9. Filter-axis catalog (the question pool)

v1 uses the first three. The rest are already-present `Game` fields that drop
into the `FinderAxis` enum + `v1Funnel` array later with no new plumbing:

| Axis | Reads | Option derivation |
| --- | --- | --- |
| Vibe ✅v1 | `collections` | non-empty collections |
| Players ✅v1 | `minPlayers`,`maxPlayers` | counts any survivor supports |
| Duration ✅v1 | `playtime` | non-empty time buckets |
| Complexity | `weight` | Light `<2` · Medium `2–3` · Heavy `3+` (non-empty only) |
| Language need | `languageDependence` | the 1–5 levels present in survivors |
| Theme | `categories` | distinct categories across survivors |
| Mechanic | `mechanics` | distinct mechanics across survivors |

## 10. Out of scope for v1 (deliberately)

- Configurable-questions **UI** (the `FinderAxis`/comparator *model* is built; the
  settings screen that edits them is later).
- Non-owned / all-database games (v1 = owned/Library only).
- AI-generated vibes.
- `userRating` capture (graceful degrade until then).
- Web port.

## 11. Build phases

1. **Logic (pure, testable):** `FinderAxis`, `FinderFlow` survivors/options,
   early-stop, ranking chain. Hard-code `v1Funnel`.
2. **Views:** `FinderStepView` + `FinderResultView`, wired to an entry point.
3. **Near-future:** capture `userRating`; settings screen to reorder/toggle axes
   and tiebreakers (reads/writes the `[FinderAxis]` + comparator list from §8/§6).

## 12. Testing

The narrowing + ranking is the only non-trivial logic and it's all pure
functions over `[Game]` — one unit test covers it: given a fixed game set,
assert the funnel narrows to the expected survivors at each step, the offered
options match, and the top-3 order obeys the tiebreaker chain (including the
`userRating == nil` fall-through).
