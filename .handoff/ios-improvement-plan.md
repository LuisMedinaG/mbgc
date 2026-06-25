# iOS improvement plan

Created: 2026-06-24

## Context

- Review scope: iOS app under `ios/`.
- Current app build: succeeds on iPhone 17 Pro simulator.
- Current test run: blocked by `MBGCTests` target config.
- Acai status: no `.feature.yaml` specs were found, so behavior changes should start by adding a feature spec.
- Project rule: do not edit `.pbxproj` or `.xcodeproj/` by hand; edit `ios/project.yml`, then run `xcodegen generate` in `ios/`.

## Suggested order

1. Unblock iOS tests.
2. Prevent destructive partial library refresh.
3. Fix API query encoding.
4. Separate search failures from empty results.
5. Decide and fix local cache isolation on logout.
6. Sync stale iOS docs.

## 0. Add spec first

Add:

- `features/ios/mobile-library.feature.yaml`

Cover these behaviors:

- Auth/session cache isolation.
- Full library sync pagination.
- Search error UX.
- Test target buildability.

After implementation:

- Add full ACID refs in tests or nearest implementation comments.
- Do not push to acai server unless the user confirms token/setup.

## 1. Fix test target build blocker

Files:

- `ios/project.yml`

Problem:

- `MBGCTests` has no generated Info.plist config.
- `xcodebuild test` fails before executing tests.

Minimal fix:

- Add `GENERATE_INFOPLIST_FILE: YES` under `MBGCTests.settings.base`.
- Run `xcodegen generate` from `ios/`.

Verify:

```sh
cd ios
xcodebuild -project MBGC.xcodeproj -scheme MBGC -destination 'platform=iOS Simulator,id=AE64B0C3-C281-4517-A4C0-06523E7C6B95' test
```

If a new error appears:

```sh
rg "<error text>" docs/runbook/
```

If no runbook match and you fix it, load the `add-runbook` skill and document the fix.

## 2. Fix destructive partial refresh

Files:

- `ios/MBGC/ViewModels/LibraryViewModel.swift`
- `ios/MBGC/Networking/APIClient.swift`
- Backend reference: `services/api/internal/catalog/handler.go`

Problem:

- Backend `/api/v1/games` defaults to page size 20.
- iOS refresh fetches only the first page.
- `LibraryViewModel.refresh` then deletes local games absent from that first page.
- Result: local library can lose games beyond page 1.

Lazy safe fix:

- Stop deleting stale local games until the client fetches a complete remote set.

Better fix:

- Teach `APIClient` to fetch all pages.
- Delete stale local rows only after collecting complete remote IDs.

Verify:

- Add a test where local storage has 25 games and API returns only page 1 of 20.
- Refresh must not delete the 5 unseen games.

## 3. Fix query encoding

Files:

- `ios/MBGC/Networking/APIClient.swift`

Problem:

- `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)` still allows query separators such as `&`, `#`, and `=`.
- A search query can accidentally change URL semantics.

Fix:

- Build URLs with `URLComponents` and `URLQueryItem`.

Verify:

- Query `foo&limit=100#x` remains one `q` value.
- It must not create an extra `limit` param or URL fragment.

## 4. Fix search error UX

Files:

- `ios/MBGC/Views/SearchView.swift`

Problem:

- `try?` converts network/server failures into `[]`.
- UI shows a false empty state instead of an error.

Fix:

- Replace `try?` with `do/catch`.
- Add `errorMessage` state.
- Show a failure state with `ContentUnavailableView` or a compact inline error.
- Keep true empty search results separate from failed search.

Verify:

- Search returning an empty successful response shows “No games found”.
- Search throwing an error shows “Search failed” or equivalent.

## 5. Fix cross-account SwiftData leak

Files:

- `ios/MBGC/Models/Game.swift`
- `ios/MBGC/ViewModels/AuthViewModel.swift`
- Possibly `ios/MBGC/Views/SettingsView.swift`

Problem:

- `Game` has global unique `id`.
- `Game` has no `userID`.
- Logout deletes the access token but leaves SwiftData rows.
- A later login can see a previous user’s local library.

Ponytail recommendation:

- MVP: clear local `Game` rows on logout.
- This is the shortest privacy-safe fix.

Only do the larger fix if the user wants per-account offline cache:

- Add `userID` to `Game`.
- Derive current user from JWT `sub` or a profile endpoint.
- Filter every SwiftData fetch by `userID`.
- Make uniqueness effectively per user, not global per game ID.

Verify:

- Persist a game.
- Logout.
- Confirm local library is empty before/after next login.

## 6. Sync docs drift

Files:

- `docs/ios-plan.md`

Problem:

- Docs still describe refresh token storage in Keychain/body.
- Current backend/iOS behavior uses an HttpOnly `mbgc_refresh` cookie.

Fix:

- Update docs only.
- Do not change auth flow without user approval; project rules say auth flow modifications require asking first.

## Notes for next agent

- Keep fixes small and separate.
- Do not manually edit `.pbxproj` or `.xcodeproj/`.
- Before debugging any new build/test error, search `docs/runbook/` for the exact error text.
- If a non-trivial new fix is discovered and no runbook entry exists, add one after resolving.
- Run the smallest relevant verification after each fix.
