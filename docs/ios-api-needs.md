# Go API changes worth making for iOS

Everything iOS needs today already exists (see `docs/ios-status.md`). These three are not
blocking, but each removes a real cost on a mobile network. Per `AGENTS.md` boundaries,
**ask first** before implementing — none are urgent.

## 1. Lite list payload for `GET /api/v1/games`

`catalog.Game` returns all ~20 fields (description, categories, mechanics, types, weight,
rating, language dependence, recommended players...) for both the list and detail
endpoints. `LibraryView`/`SearchView` only render name, year, thumbnail. Add
`?fields=lite` (or a separate `GameSummary` projection) so list payloads stop carrying
detail-only data over a cellular connection. Detail view keeps the full shape.

## 2. Async BGG sync job

Already tracked as architecture-flaws.md F-05. `POST /api/v1/import/sync` runs the BGG
fetch synchronously inside the request — on a large collection or a flaky mobile network
this risks client timeout with no way to know if the sync actually completed server-side.
Minimum viable: `202 {job_id}` + `GET /api/v1/import/jobs/{id}` for status/counters. This is
the highest-value change for iOS specifically, since phones lose connectivity mid-request
far more often than the web client does.

## 3. Incremental library sync (`updated_since` or ETag)

Not urgent now that `APIClient.listGames` walks all pages — but every pull-to-refresh
still re-downloads the full collection. A `?updated_since=<timestamp>` filter (or ETag/
304 support) would let iOS fetch only changed rows. Worth doing once the library grows
large enough that a full refetch is noticeably slow; skip until then.
