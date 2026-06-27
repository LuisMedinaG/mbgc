# iOS App Store readiness review

Date: 2026-06-26

Scope: `ios/` only.

Reviewer stance: senior iOS, SwiftUI, UX, and security review.

Verification: `xcodebuild -project MBGC.xcodeproj -scheme MBGC -destination 'platform=iOS Simulator,id=AE64B0C3-C281-4517-A4C0-06523E7C6B95' test` passed. The suite ran 2 parser tests.

## Summary

The iOS app has a solid local-first base: SwiftUI, SwiftData, no backend client, zero third-party dependencies, and a single paced BGG XML client.

The app is not App Store ready yet.

Minimum blockers are token handling, privacy manifest/App Privacy setup, import data integrity, and Library invariant bugs.

## High-priority findings

### P1 - Release embeds a BGG token

`ios/project.yml` maps the build setting `BGG_TOKEN` into `BGGToken` in the app Info.plist for both Debug and Release.

`ios/MBGC/Info.plist` contains `BGGToken`.

`ImportView` reads `Bundle.main.object(forInfoDictionaryKey: "BGGToken")`.

`BGGClient` sends it as an authorization header.

Impact: an App Store binary exposes the token to anyone who inspects the bundle.

Recommendation: do not ship a build-time BGG token. Since public BGG collections work without it, omit `BGGToken` from Release. Rotate the local token if it is real.

Relevant files:

- `ios/project.yml`
- `ios/MBGC/Info.plist`
- `ios/MBGC/Views/ImportView.swift`
- `ios/MBGC/Networking/BGGClient.swift`
- `ios/Secrets.xcconfig`

### P1 - Privacy manifest is missing

The app uses `UserDefaults` for BGG username, cached IDs, cooldown date, and appearance.

Apple requires privacy manifest declarations for required-reason APIs such as UserDefaults.

Impact: App Store Connect upload/review risk.

Recommendation: add `PrivacyInfo.xcprivacy` and complete App Store privacy answers. Disclose that a BGG username is sent to BoardGameGeek to fetch public collection data.

Relevant files:

- `ios/MBGC/Views/ImportView.swift`
- `ios/MBGC/Views/SettingsView.swift`

### P1 - Duplicate CSV IDs can break import

`CSVRow.id` is `bggId`.

`parseCSV` appends rows without deduping.

`importCSV` builds `allIds` from all preview rows, preserves duplicates, fetches duplicate IDs, and inserts a new `Game` per duplicate.

`Game.bggId` is `@Attribute(.unique)`.

Impact: duplicate CSV rows can fail `modelContext.save()` and abort import.

Recommendation: dedupe IDs once after parsing or before import. Preserve first display name.

Relevant files:

- `ios/MBGC/Views/CsvImportView.swift`
- `ios/MBGC/Models/Game.swift`

### P1 - Library invariant can be broken

The default Library is intended to contain imported local games.

`Move All` can move games out of Library by removing relationships from `source.games`.

`Delete All` removes relationships from the current collection but does not delete `Game` rows.

Impact: games can exist locally while no longer appearing in Library.

Recommendation: if source is default Library, either disable move/delete relationship actions or define delete as deleting `Game` rows globally with explicit confirmation.

Relevant files:

- `ios/MBGC/Views/VibesView.swift`
- `ios/MBGC/Models/Collection.swift`

## Medium-priority findings

### P2 - Spec mismatch: destination picker gets all owned games

`bgg-import.SYNC.3` says only newly imported games are added to the selected local collection.

`ImportView` sets `selectedGames = LocalLibrary.games(matching: bggIds, in: modelContext)`, which includes existing local games too.

Impact: spec and product behavior disagree.

Recommendation: either change code to pass only `newGames`, or update the spec if selecting the whole owned collection is intended.

Relevant files:

- `features/ios/bgg-import.feature.yaml`
- `ios/MBGC/Views/ImportView.swift`

### P2 - UI says no expansions, parser does not filter expansions

`CollectionPickerView` displays "Owned games only - No expansions".

`BGGXMLParser.parseCollectionResponse` accepts any `<item objectid>` and ignores `subtype`.

Impact: users may import expansions despite UI promise.

Recommendation: either filter `subtype == "boardgame"` at parse time or remove the claim.

Relevant files:

- `ios/MBGC/Views/ImportView.swift`
- `ios/MBGC/Networking/BGGXMLParser.swift`

### P2 - Destination picker selection is index-based

`CollectionPickerView` stores `selectedIndex`.

`createAndSelect` sets `selectedIndex = max(0, collections.count - 1)` before the `@Query` array refreshes.

`.onChange(of: collections.count)` calls `setDefaultSelection()`, which resets selection to Library.

Impact: a user can create a new collection and still import into Library.

Recommendation: track selected collection by `PersistentIdentifier`, not array index.

Relevant file:

- `ios/MBGC/Views/ImportView.swift`

### P2 - Save failures are silently ignored

Several destructive or mutating collection operations use `try? modelContext.save()`.

Impact: failed saves become invisible UI/data drift.

Recommendation: show a small alert or error state for mutating actions.

Relevant file:

- `ios/MBGC/Views/VibesView.swift`

## Lower-priority findings

### P3 - CSV parser is brittle

The parser handles simple comma/quote cases but not multiline quoted fields or escaped quotes.

It reads the full file with `String(contentsOf:)`.

Recommendation: acceptable for small BGG exports, but add a tiny test for duplicate IDs, quoted commas, and escaped quotes before widening CSV support.

Relevant file:

- `ios/MBGC/Views/CsvImportView.swift`

### P3 - Year filter is hard-coded

`FilterField.yearPublished.range` is `1970...2026`.

Impact: older games are excluded and this goes stale next year.

Recommendation: use a wider static range or derive upper bound from current year.

Relevant file:

- `ios/MBGC/Views/FilterView.swift`

## Structure review

Good:

- Local-first boundary is clean.
- No backend API client is present in iOS.
- `BGGClient` is isolated as an actor.
- SwiftData models are small.
- `@Observable` view models are `@MainActor`.
- Zero third-party dependencies keeps review and maintenance simple.

Needs cleanup:

- `VibesView.swift` is too large and owns list, detail, sheets, selection, filters, share, and mutation flows.
- Split `VibesView.swift` into `CollectionsListView`, `CollectionDetailView`, collection sheets, and collection actions.
- Keep `project.yml` as source of truth; do not manually edit `.xcodeproj`.
- Empty `Utilities/` and `Resources/` folders should be deleted unless they will be used immediately.

## UI/UX recommendations

The app currently opens to "Discover Coming Soon".

For App Store review and first-run UX, the first screen should offer real actions: import from BGG and import CSV.

Import is core product behavior, so it should not live only under Settings.

Icon-only buttons need accessibility labels and large enough tap targets.

The collection detail action pill is compact but dense; separate destructive actions from filter/sort/select.

Dynamic Type needs a pass. Fixed 52 pt input text and compact custom controls can break at large accessibility sizes.

The app is portrait-only and full-screen. This is acceptable for an iPhone-first app, but weak on iPad.

## Minimum App Store checklist

- Remove bundled BGG token from Release.
- Rotate current BGG token if it is real.
- Add `PrivacyInfo.xcprivacy`.
- Fill App Store Connect privacy nutrition labels.
- Publish privacy policy URL and support URL.
- Make first launch actionable; do not open on a placeholder-only Discover screen.
- Verify no `.env`, `.xcconfig` secrets, or local build artifacts are packaged.
- Archive Release and inspect final app Info.plist.
- Test first launch with empty database.
- Test no-network import errors.
- Test BGG 202/429 retry behavior.
- Test duplicate CSV IDs.
- Test a large real BGG CSV export.
- Test dark mode.
- Test Dynamic Type accessibility sizes.
- Test VoiceOver labels for icon-only controls.
- Test device performance, not only simulator.
- Prepare App Review notes: no login, public BGG import, sample username or sample CSV.
- Run TestFlight before App Review.

## Suggested smallest fix order

1. Remove Release token embedding.
2. Add privacy manifest.
3. Dedupe CSV IDs.
4. Preserve Library invariant.
5. Fix destination picker selection by ID.
6. Replace first-screen placeholder with import actions.
7. Add focused tests for parser/import edge cases.

## Spec notes

The code currently deviates from `bgg-import.SYNC.3`.

Agents should update the spec first if product intent is to add the whole owned BGG set to a chosen collection.

If product intent is only newly imported games, fix `ImportView` to pass only `newGames` into `CollectionPickerView`.
