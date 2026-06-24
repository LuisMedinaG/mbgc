---
name: importing-from-bgg
description: Changes how this app fetches data from BoardGameGeek — the custom /xmlapi2/thing XML parser, gobgg usage, rate limiting, and the Full Refresh backfill requirement. Use when the user asks to pull new data from BGG, parse a new BGG poll or stat, fix a BGG sync bug, adjust rate limiting, or backfill existing collections.
---

# Importing data from BGG

BGG integration lives in `services/importer/internal/bgg/`. Two entry points:

- `c.bgg.GetCollection(...)` — gobgg's `GetCollection`, used for "what games does user X own".
- `c.fetchThingsParsed(ctx, ids...)` — **custom** XML fetch for `/xmlapi2/thing`, used for per-game metadata.

Both go through the same throttled, authenticated `http.Client`, so rate limiting is shared.

## Why a custom /thing fetch

`gobgg.ThingResult` doesn't expose poll data. We need `language_dependence` and `suggested_numplayers` polls, so `fetchThingsParsed` parses `/xmlapi2/thing` directly using the XML structs in `bgg.go` (`bggThingXMLItems`, `bggPollXML`, `bggStatisticsXML`, etc.). This gives every field — polls, stats, links — in one request.

**Don't** replace this with gobgg. **Don't** duplicate it with a second `http.Client`. Reuse `c.httpClient`.

## Shared HTTP client

`newHTTPClient` wraps two transports:

1. `authTransport` — sets the BGG auth token (or cookie fallback) and `User-Agent` on every request. Without this, `/thing` returns 401 which surfaces as `"XML decoding failed: EOF"`.
2. `throttledTransport` — paces requests at `bggRPS = 2` per second and transparently retries HTTP 429 with `Retry-After` backoff.

Any new BGG endpoint you add should go through `c.httpClient.Do(req)` to inherit both behaviours.

## Adding a new field parsed from /thing

**For a stat** (e.g. BGG rank, owners count):
1. Extend `bggRatingsXML` or `bggStatisticsXML` with a new `bggSimpleAttr` / nested struct.
2. Parse and set in `bggItemToGame`.

**For a poll** (e.g. "suggested player age"):
1. Add a `parseXxx(polls []bggPollXML) T` helper next to `parseLanguageDependence` / `parseRecommendedPlayers`. Match by `p.Name == "bgg_poll_name"`.
2. Call it from `bggItemToGame` and set the field on the returned model.

**For a link** (e.g. designers, artists — BGG uses `boardgame<type>` link elements):
1. Add a `case "boardgame<type>":` branch in the `for _, l := range item.Link` loop.
2. Collect into a slice, then `strings.Join(x, ", ")` onto the field.

Poll parsing conventions:
- Treat missing polls or zero votes as a zero value (0, "", empty slice). Don't error.
- For ranked polls, pick the option with the most votes.
- Strip `"+"` suffixes from player counts (`"5+" → "5"`) so numeric filters work.

## Adding a new /xmlapi2 endpoint

Build the URL, create a request with `http.NewRequestWithContext`, call `c.httpClient.Do(req)`. Mirror the retry-on-empty pattern from `fetchThingsParsed` — BGG returns an empty 200 while it queues large requests. Retry up to 4 times with exponential backoff.

```go
const bggFoo = "https://boardgamegeek.com/xmlapi2/foo"

func (c *Client) fetchFoo(ctx context.Context, arg string) (FooResult, error) {
    const maxAttempts = 4
    delay := 500 * time.Millisecond
    u := bggFoo + "?arg=" + url.QueryEscape(arg)
    for attempt := 1; ; attempt++ {
        req, _ := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
        resp, err := c.httpClient.Do(req)
        if err != nil { return FooResult{}, err }
        body, _ := io.ReadAll(resp.Body); resp.Body.Close()
        var out FooResult
        if err := xml.Unmarshal(body, &out); err != nil || out.isEmpty() {
            if attempt >= maxAttempts { return FooResult{}, fmt.Errorf("bgg: no data after %d attempts", maxAttempts) }
            select { case <-time.After(delay): case <-ctx.Done(): return FooResult{}, ctx.Err() }
            delay *= 2; continue
        }
        return out, nil
    }
}
```

## Rate limiting

- `bggRPS = 2` — don't raise it; don't add a second ticker; don't bypass the transport.
- Batch IDs: `bggThingBatchSize = 20` and `chunkIDs`. Keep batches ≤20 IDs.

## Backfilling existing data (Full Refresh)

`ImportCollection` has two modes:

- **Normal sync** (`fullRefresh=false`) — fetches `/thing` only for BGG IDs the user doesn't already own.
- **Full Refresh** (`fullRefresh=true`) — fetches every owned item and calls `UpdateGame` to refresh metadata.

**Any new BGG-sourced field is invisible on existing collections until a Full Refresh runs.** Tell the user:

> To backfill existing games, run a Full Refresh: check the "Full Refresh" box on the Import page (admin-only), or call `POST /api/v1/import` with body `{"full_refresh": true}`.

This is admin-gated because it fans out N `/thing` requests per user.

## Debugging

- `"XML decoding failed: EOF"` → usually 401. Check `BGG_TOKEN`/cookies and that the request went through `authTransport`.
- Empty `result.Items` with no error → BGG is queueing. The retry loop handles this.
- 429s in logs but sync completes → normal; `throttledTransport` is working. If frequent, lower `bggRPS`.
- Polls returning 0/"" → BGG returned zero votes or the poll name changed. Log `item.Poll` and check names.

## Verification

```sh
cd services/importer && make test-v   # BGG tests stub the HTTP client
# Manual smoke test: trigger an import and check the importer service logs
# Verify new fields via Supabase Studio or:
# supabase status → connect with DATABASE_URL → SELECT name, new_field FROM games.games LIMIT 5;
```
