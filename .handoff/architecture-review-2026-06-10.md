# Architecture Review — Pending Work

Comprehensive review of the mbgc API + web + infra conducted on **2026-06-10** ahead of the
iOS app launch. Goal: production-ready backend, secure for a public iOS client, scalable
from 1 → 100s → 1000s of users.

The code is in strong shape overall — clean package layout, multi-tenancy enforced at the
SQL layer, JWKS-based JWT validation, spec-driven development with acai, Terraform-managed
infra, embedded migrations with dirty-state recovery, 66.8% test coverage. The items below
are the gaps that surfaced under scrutiny.

Status: **no code changes yet**. This doc captures findings only. Pick up items via the
GH issues linked in each section.

---

## Severity Legend

- **CRITICAL** — must fix before iOS app ships to TestFlight / App Store
- **HIGH** — should fix before public iOS launch
- **MEDIUM** — fix at 100+ users
- **LOW** — fix at 1000+ users

---

## CRITICAL

### 1. `SetGameCollections` is not transactional — silent data loss

**File:** `services/api/internal/game/store.go:225-254`
**Why:** The store does `DELETE FROM games.collection_games WHERE game_id = $1` then loops
`INSERT` for each collection ID — with no `BEGIN/COMMIT`. If INSERT #3 of 5 fails (DB
constraint, connection drop, timeout), the game silently loses collections 4 and 5 with no
error returned to the handler, no log emitted, and no way for the client to know. For an
iOS user who just spent time curating "vibes" — a destructive, invisible corruption.

**Design shape:** Wrap the DELETE + INSERTs in a single `pgx.Tx`. On any error, `Rollback`
restores the previous state. The ownership-existence check and the collection-ownership
count check must also live in the same transaction, otherwise TOCTOU bugs let a user attach
a game to a collection that was deleted between the two queries.

**Constraints:**
- Atomic: the game either has exactly the requested collections after the call, or zero
  (revert), never a partial set.
- The validation count check (`count != len(collectionIDs)`) must run inside the same
  transaction or be eliminated in favor of a `SELECT ... FOR UPDATE` against the collections
  table.
- No behavior change for the success path.
- Add a handler test that injects a failure on the second INSERT and asserts the row count
  in `collection_games` is unchanged.

---

### 2. No OpenAPI / Swagger spec — iOS development blocked

**Files:** missing entirely; should land at `services/api/openapi.yaml`
**Why:** Without a contract spec, iOS development has to either hand-roll a Swift client
against the running API (drift-prone, no compile-time safety) or reverse-engineer from
cURL/network tab. More importantly, the spec is what makes the API *navigable* for a new
developer (human or LLM) and what makes breaking changes detectable. This is the single
highest-leverage gap for the iOS launch.

**Design shape:** A single `openapi.yaml` checked into the repo, generated or hand-written
covering all `/api/v1/*` routes. Generate it from the Go handlers (chi-style reflection is
not viable here since we use stdlib mux) — either hand-write the initial version, or add a
code annotation layer that produces it. Wire it into CI as a contract test: a generated
client (or `swagger-cli validate`) must pass on every PR.

**Constraints:**
- One source of truth — handlers do not define the spec, the spec does not redefine the
  handlers; one generates the other.
- All envelope shapes (`envelope.Response`, `envelope.ListResponse`, `envelope.NewError`)
  must be in the spec as component schemas.
- Error responses documented per route with the `apierr` code + HTTP status.
- iOS-side: feed the spec to `openapi-generator` to produce a Swift client; check the
  generated code into the iOS repo.
- Backward-compat: documenting the current API is non-breaking; any subsequent change must
  be a deliberate spec PR.

---

## HIGH

### 3. Auth handler can hang indefinitely on Supabase

**File:** `services/api/internal/auth/handler.go` — `supabaseAuthClient` constructed with
whatever `*http.Client` is passed in.
**Why:** `main.go` passes `httpx.DefaultClient` (10s timeout — good). The test file at
`handler_test.go` passes `http.DefaultClient` (no timeout). In the running app this is fine,
but it means: (a) the pattern is inconsistent and fragile — any future caller passing
`http.DefaultClient` re-introduces the hang, (b) the integration test `TestLogin_SupabaseUnreachable`
uses `http://127.0.0.1:1` and times out at the 10s mark — tests are slow.

**Design shape:** Make the `supabaseAuthClient` require a `*http.Client` with a sane timeout
at construction time. If the caller passes `http.DefaultClient`, refuse to build. This makes
the timeout a type-level invariant, not a runtime hope.

**Constraints:**
- No behavior change in production (`httpx.DefaultClient` already has a 10s timeout).
- Test file updated to use `httpx.DefaultClient` or a test client with a short timeout.
- `supa := httptest.NewServer(...)` in existing tests stays — that path has its own implicit
  timeout from the listener.

---

### 4. `/readyz` doesn't check the database

**File:** `services/api/cmd/server/main.go:127-130`
**Why:** The endpoint returns `{"status":"ok"}` unconditionally. Cloud Run's health check
will route traffic to a container whose `pgxpool` has been disconnected (e.g., Postgres
restarted, network blip, Supabase maintenance window) — every request 500s until the pool
reconnects. Liveness probes should not depend on the DB, but readiness must.

**Design shape:** Two endpoints. `/healthz` — pure liveness, no deps, always returns 200 if
the process is up. `/readyz` — pings the DB (`pool.Ping(ctx)` with a 2s timeout) and the JWT
verifier's JWKS cache, returns 200 only if both are healthy. Cloud Run wired to `/readyz`
for the readiness probe, `/healthz` is not configured (default behavior suffices).

**Constraints:**
- `Ping` must have a short context timeout (2s) — do not use the request's context directly
  for readiness probes, or a slow DB will block the response.
- Failure response shape matches the standard error envelope so the iOS client can render it
  identically to other errors.
- No new dependencies.

---

### 5. `config.Load()` calls `os.Exit(1)` — impossible to test error paths

**File:** `services/api/internal/config/config.go:47-51`
**Why:** `mustenv` kills the process on missing required env vars. The existing test file
works around this by *not* asserting the `wantErr` cases (they all early-return with a
blank `Load()` result), so the failure path is genuinely untested. This pattern also
prevents any caller from handling missing config gracefully — impossible to wrap startup
in a retry, or to surface a friendlier error to the user.

**Design shape:** `Load() (Config, error)`. The `mustenv` semantics become the entry point's
responsibility: `cmd/server/main.go` calls `Load`, logs the error, and exits. The function
itself is pure and testable.

**Constraints:**
- All existing call sites updated (only `main.go`).
- The test file's `wantErr` cases become real assertions on the returned error.
- Validation surface: `Load` returns a single aggregated error (use `errors.Join`) so a
  missing `DATABASE_URL` and missing `SUPABASE_URL` are reported together, not one at a time.

---

### 6. No rate limiting on non-auth endpoints

**File:** `services/api/cmd/server/main.go:110-116` — `httpx.RateLimiter(5, 10)` applied
only to auth routes.
**Why:** BGG sync, game CRUD, collection CRUD, and discover are all unbounded. A misbehaving
iOS client (retry loop, accidental N+1 UI) can saturate the API. At one user this is a
non-issue. At 100 users with one bad client, it's a partial outage.

**Design shape:** A two-tier limiter at middleware level. Outer tier — per-IP, generous
(30 req/s), catches unauthenticated abuse. Inner tier — per-user (from JWT subject), tighter
(10 req/s), catches authenticated abuse. Both use a token bucket with burst capacity. The
existing `httpx.RateLimiter` is the right primitive — needs only new instances wired in.

**Constraints:**
- Limiter state must work across multiple Cloud Run instances. At 1 user, in-memory is
  fine; at 100+, swap the backing store for Redis without changing the call site.
- 429 responses include `Retry-After` and the standard error envelope.
- Auth endpoints keep their existing 5 req/s per-IP limit (tighter, since brute force is
  the threat).
- No new client-visible behavior on the happy path.

---

### 7. `pgxpool` uses default config

**File:** `services/api/cmd/server/main.go:87-90` — `pgxpool.New(ctx, cfg.DatabaseURL)`
**Why:** Default config is `MaxConns=4`, `MinConns=0`, `MaxConnLifetime=0` (unlimited),
`MaxConnIdleTime=30min`. At 1 Cloud Run instance with 1 user this is fine. At multiple
instances with concurrent requests, you exhaust the pool (max 4 conns per instance) and
the default 30min idle timeout means cold instances pay full TCP+TLS handshake to Supabase
on the first request.

**Design shape:** Explicit `pgxpool.Config`:
- `MaxConns` = 10 per instance (4-10× headroom over default; tune to Cloud Run max
  instances × per-instance limit)
- `MinConns` = 2 to keep warm
- `MaxConnLifetime` = 30min (Supabase prefers short-lived connections)
- `MaxConnIdleTime` = 5min
- `HealthCheckPeriod` = 1min (auto-reconnect dead conns)

**Constraints:**
- No code in handlers/store needs to change.
- Add a `pgxpool.Stat()`-based `/readyz` health check (ties to item #4).
- Numbers above are starting points; tune from real Cloud Run metrics once deployed.

---

## MEDIUM

### 8. `SyncResult.Failed` leaks internal error strings to clients

**File:** `services/api/internal/importer/model.go:8` — `Failed []string`
**Why:** BGG sync returns raw error messages (`"bgg: 503 Service Unavailable"`,
`"fetching BGG collection for user: timeout"`). These leak internal service names, transport
details, and timing information — useful reconnaissance for an attacker probing the API.

**Design shape:** Replace with structured failures:
```go
type ImportFailure struct {
    BGGID  int    `json:"bgg_id"`
    Reason string `json:"reason"`  // one of: "not_found", "rate_limited", "fetch_error", "invalid_data"
}
```
Map internal errors to these reasons in the service layer. Keep the detailed errors in
`slog` logs (request-ID correlated) for operator debugging.

**Constraints:**
- The web client and iOS client currently display the string — they need a fallback for
  unknown reasons.
- Slog logs preserve the full detail with request-ID correlation (already exists via the
  `RequestID` middleware).
- No behavior change on the success path.

---

### 9. `Discover` has hardcoded `LIMIT 100`, no pagination

**File:** `services/api/internal/game/store.go:295`
**Why:** Discover returns all games in a collection matching the filters, capped at 100.
At 100+ games in a collection (common for hobby boardgamers), the user can't see the rest.
No offset parameter, no "load more" affordance.

**Design shape:** Add `Page` and `Limit` to `DiscoverFilter`, default 50, max 100. Handler
parses query params the same way `ListGames` does (clamping to safe bounds). Store uses
the same `LIMIT/OFFSET` pattern as `ListGames`.

**Constraints:**
- The collection metadata (`*Collection`) should still be returned alongside the paged
  games.
- Backward compatible: existing clients that don't pass `page`/`limit` get the first 50
  (down from 100) — acceptable since the endpoint was never paginated before.
- Handler test added for clamping.

---

### 10. `SetGameCollections` uses loop of INSERTs instead of batch

**File:** `services/api/internal/game/store.go:247-251`
**Why:** Beyond the transaction issue (#1), the loop is N round-trips for N collections.
`UNNEST` does it in one.

**Design shape:** Single statement:
```sql
INSERT INTO games.collection_games (collection_id, game_id)
SELECT unnest($1::bigint[]), $2
```

**Constraints:**
- Pairs with the transactional fix from #1.
- 10× reduction in DB round-trips for a 10-collection assign.

---

### 11. Missing DB indexes on hot query paths

**Files:** `services/api/migrations/*.sql`
**Why:** No GIN index on `search_vector` means full-text search degrades to sequential scan
as the games table grows. No B-tree index on `(user_id, name)` makes `ORDER BY name`
require a sort. No index on `collection_games(game_id)` or `(collection_id)` makes the
joins in `ListCollections` and `Discover` slow.

**Design shape:** Migration `005_indexes.up.sql` adding:
- `CREATE INDEX games_user_id_name_idx ON games.games (user_id, name);`
- `CREATE INDEX games_search_vector_idx ON games.games USING GIN (search_vector);`
- `CREATE INDEX collection_games_game_id_idx ON games.collection_games (game_id);`
- `CREATE INDEX collection_games_collection_id_idx ON games.collection_games (collection_id);`
- `CREATE INDEX games_user_id_bgg_id_idx ON games.games (user_id, bgg_id);` (the unique
  constraint should already create this — verify)

**Constraints:**
- `CREATE INDEX CONCURRENTLY` is not possible inside a single transaction migration;
  accept the brief lock for a table this size, or split into a manual ops step.
- Verify with `EXPLAIN ANALYZE` on the hot queries before/after.

---

### 12. In-memory rate limiter doesn't work with multiple Cloud Run instances

**File:** `pkg/shared/httpx/rate_limiter.go`
**Why:** The limiter's bucket state lives in-process. Cloud Run auto-scales to multiple
instances — a user getting limited on instance A has full quota on instance B. Effective
limit is `per_instance_limit × instance_count`.

**Design shape:** Two options. **Option A (faster):** Pluggable limiter interface with
both in-memory and Redis backends. In-memory for local dev (1 instance), Redis for prod.
**Option B (simpler):** Defer until 100+ users. In-memory works for the 1-user case
entirely, and is acceptable for ~10-50 users given how Cloud Run cold-starts.

**Constraints:**
- If Option A: add `github.com/redis/go-redis/v9` dep, new `RateLimiterRedis` constructor.
- Per-user identity (from JWT) is the partition key for the inner tier.
- TTL on the Redis keys prevents unbounded growth from deleted users.

---

### 13. No request/response compression

**File:** `services/api/cmd/server/main.go` — middleware chain has no compression
**Why:** Game list responses with full metadata (categories, mechanics, types, etc.) are
50-200KB per page. iOS users on cellular see slow loads. Cloud Run supports gzip at the
edge (`--no-gpu` is unrelated), but application-level `gzip` with `Content-Encoding` gives
explicit control.

**Design shape:** `klauspost/compress` middleware (or stdlib `compress/gzip` in a thin
wrapper) in the middleware chain, gzip level 5. Applied after the body size limit (so we
don't compress a 1MB body that we're about to reject) and before the route handlers.

**Constraints:**
- Skip compression for already-compressed content types (images served via Storage URLs
  are not handled by this API — N/A).
- Add `Vary: Accept-Encoding` to responses.
- Adds ~1-2ms CPU overhead per request — negligible.

---

### 14. BGG sync is synchronous — will timeout at scale

**File:** `services/api/internal/importer/service.go` — `Sync` blocks the request for the
full duration of fetching + parsing + upserting.
**Why:** At ~2 req/s BGG rate limit and 20 games per batch, a 500-game collection takes
~250s. Cloud Run's request timeout is 300s by default. A 600-game collection (a real
hobbyist count) blows past it. The user stares at a spinner that eventually 504s.

**Design shape:** Async job pattern. `POST /api/v1/import/sync` enqueues a job (in-memory
channel for now, Redis-backed list at scale), returns 202 with a `job_id`. New endpoint
`GET /api/v1/import/sync/{job_id}` polls status. Service processes jobs in a background
worker pool sized to BGG rate limits.

**Constraints:**
- Existing 202-response contract: return `{ job_id, status: "pending" }`.
- Status responses: `pending` → `running` → `completed` (with counts) | `failed` (with
  sanitized reason).
- Backward compat: the current synchronous behavior can be kept behind a query param
  (`?sync=async`, default `async` after rollout) for a deprecation period.
- Job state must survive Cloud Run instance restart (Redis-backed, not in-memory) at
  scale.

---

## LOW (iOS app specific)

### 15. No push notification infrastructure

**File:** N/A — entirely new
**Why:** Board game collection features that benefit from push: "BGG sync completed",
"new game added by a friend", "rate your last played game". Requires FCM (Android) +
APNs (iOS) setup, device registration storage, and a notification service.

**Design shape:** A new `services/api/internal/notifications/` package: device token CRUD
(supabase table), a `Notify(userID, event, payload)` function, and a worker that calls
FCM/APNs. Defer until iOS v1.1 (post-launch).

**Constraints:** Out of scope for the iOS v1.0 launch. Track in roadmap.

---

### 16. No `X-Client-Version` or `X-Platform` header support

**File:** N/A — new middleware
**Why:** The iOS app should identify its version in every request. Enables: server-side
feature flags (force-upgrade notice for v1.0.0 with a known bug), per-version analytics,
server-controlled iOS deprecation.

**Design shape:** A new middleware that reads `X-Client-Version` and `X-Platform: ios`
headers, attaches them to the request context, and logs them in the structured request log.
No rejection on missing headers (web client doesn't set them).

**Constraints:** Web client unaffected. iOS client sets them in its API client config.

---

### 17. CORS is configured for the web origin only

**File:** `services/api/cmd/server/main.go:120-128` — `cfg.AllowedOrigin` is a single string
**Why:** If the iOS app uses WKWebView at any point (for OAuth, payment, or a webview-based
screen), it needs its own origin allowed. Native URLSession is CORS-immune.

**Design shape:** Convert `AllowedOrigin` to `AllowedOrigins []string` (comma-separated
env var). Native iOS URLSession doesn't send Origin headers, so the current CORS policy
is a no-op for them — safe to expand.

**Constraints:** Backward compat: single-origin deployments still work by passing a
comma-separated list with one entry.

---

## Sequencing Note

**Before iOS TestFlight (must):** #1, #2, #3, #4, #5, #6, #7

**Before public iOS launch:** #8, #9, #10, #11, #13, #16, #17

**At 100+ users:** #12, #14

**Post-launch (iOS v1.1+):** #15

By leverage-per-effort within the "before TestFlight" set: **#1** (30min, data integrity),
**#5** (1hr, unlocks testability of config), **#7** (30min, prod stability), **#4** (30min,
prod observability), **#6** (2hr, DoS protection), **#3** (1hr, defense in depth), **#2**
(4-8hr, iOS foundation).

---

## Cross-References

- `pending-security-design.md` — items 1-3 of the earlier security work (monitoring,
  dependency scanning, Content-Type) are now complete or tracked in GH issues.
- `features/api-layer.feature.yaml` — the spec source for envelope + error contracts.
- `infra/AGENTS.md` — infra-side change procedures if any of the medium items touch
  Cloud Run config.
