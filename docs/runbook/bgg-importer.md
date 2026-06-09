# BGG Importer Troubleshooting

Issues and fixes for the BoardGameGeek sync + CSV import path
(`services/api/internal/importer/`).

## Test BGG user

The shared dev/test BGG account on boardgamegeek.com is **`mytestuser`**.
Use it whenever you need a real BGG handle to exercise the sync path —
it has a small public collection so the sync completes quickly and
predictably.

```sh
# Set the BGG username on your local profile
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"Lhmg1998."}' | jq -r '.data.access_token')

curl -s -X PUT http://localhost:8080/api/v1/profile/bgg-username \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"bgg_username":"mytestuser"}'

# Trigger a sync (admin = 20 syncs/day, regular user = 3 syncs/day)
curl -s -X POST http://localhost:8080/api/v1/import/sync \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{}'
```

> The JWT subject (e.g. `admin`) is the local account name — the
> `bgg_username` field in the profile is the *BGG* handle and is what
> gets passed to the BGG API. Mixing these up yields
> `XML decoding failed: expected element type <items> but have <errors>`
> because BGG can't find a user with the JWT subject as their handle.

## Common errors

| Error | Cause | Fix |
|---|---|---|
| `XML decoding failed: expected element type <items> but have <errors>` | BGG username not found, or the BGG API returned an error XML. Almost always the username being passed doesn't match a real BGG account. | Verify the profile's `bgg_username` is a real BGG handle. Use `mytestuser` for local dev. |
| `ERROR: null value in column "types" of relation "games"` | The upsert was passing a `nil` slice for a NOT NULL `text[]` column. | Always coerce nil slices to `[]string{}` / `[]int{}` before persisting. See `game.emptySlice` / `game.emptyIntSlice`. |
| `sync_ok ... game_count=0` even though the collection has items | The user hasn't set `bgg_username` on their profile. Sync is a no-op without it. | Set the BGG username via `PUT /api/v1/profile/bgg-username`. |
| `401 invalid token` from BGG (`/thing` returns empty 200) | The BGG auth token is missing or expired, and the request didn't go through the `authTransport`. | Check `BGG_TOKEN` in `services/api/.env`. All BGG HTTP calls must go through `c.httpClient`, not a raw `http.Client`. |

## BGG rate limiting

`bggRPS = 2` requests/second. A ~120-game collection takes ~1 minute.
The `throttledTransport` paces requests and transparently retries 429s
honoring the `Retry-After` header (1s → 2s → 4s, max 3 retries).

If you see 429s in the logs but the sync completes — that's normal.
If 429s are *frequent*, lower `bggRPS` rather than raising it.

## Backfilling existing data

The normal sync path only fetches `/thing` for BGG IDs the user doesn't
already own. To refresh metadata on games already in the collection,
trigger a Full Refresh (admin only):

```sh
curl -s -X POST "http://localhost:8080/api/v1/import/sync?full_refresh=true" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{}'
```

Or in the UI: Import page → "Full Refresh" checkbox → Sync.
