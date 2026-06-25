# Testing Runbook

## Coverage & CI

- **Threshold:** 50% minimum on `services/api/...`
- **Enforcement:** CI fails if coverage drops below 50%
- **Command:** `make test` runs `go test -race -coverprofile` and checks threshold

**Why 50%?** Catches regressions on critical paths (handlers, config, auth) without requiring 100% on boilerplate.

## Go Backend Patterns

### Handler Tests (no DB)

Each package (game, auth, profile, importer) defines a store interface:
```go
type gameStore interface {
  ListGames(ctx, userID, filter) ([]Game, int, error)
  GetGame(ctx, id, userID) (*Game, error)
  // ...
}
```

Tests mock this interface as a struct with function fields:
```go
type mockGameStore struct {
  listGamesFn func(...) ([]Game, int, error)
}
func (m *mockGameStore) ListGames(...) (...) { return m.listGamesFn(...) }
```

**Why?** Avoids DB dependency, tests business logic in isolation, enables fast feedback.

**Pattern file:** `internal/{game,auth,profile,importer}/handler_test.go`

### HTTP Handler Testing

Use `httptest.NewRecorder()` to capture responses:
```go
w := httptest.NewRecorder()
r := httptest.NewRequest("GET", "/api/v1/games", nil)
h.ListGames(w, r)
```

Verify status, headers, and body JSON:
```go
if w.Code != http.StatusOK { t.Fatalf("expected 200, got %d", w.Code) }
var resp envelope.ListResponse[Game]
json.NewDecoder(w.Body).Decode(&resp)
```

**Why?** Fast, no network overhead, full HTTP semantics (status codes, headers, bodies).

### External API Mocking (Supabase, BGG)

Use `httptest.Server` to mock external endpoints:
```go
server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
  // verify headers (Authorization, apikey)
  // verify request body
  w.WriteHeader(http.StatusCreated)
  json.NewEncoder(w).Encode(response)
}))
defer server.Close()
cfg.SupabaseURL = server.URL
```

Verify the client sends correct headers, payloads, and handles errors (e.g., 500, 422, timeouts).

**Why?** Tests error paths (network failures, API conflicts) without hitting real services.

**Examples:** `internal/seed/seed_test.go` (Supabase mocks), `internal/importer/handler_test.go` (BGG mocking)

### Config & Utility Tests

Direct unit tests for pure functions and configuration:
```go
func TestSanitizeDatabaseURL(t *testing.T) {
  tests := []struct{ input, want string }{...}
  for _, tt := range tests {
    if got := sanitizeDatabaseURL(tt.input); got != tt.want {
      t.Errorf(...)
    }
  }
}
```

Isolate environment variables with cleanup:
```go
orig := os.Environ()
os.Clearenv()
defer func() {
  os.Clearenv()
  for _, pair := range orig { /* restore */ }
}()
```

**Why?** Deterministic, no side effects, easy to add cases.

**Examples:** `internal/config/config_test.go`

## Frontend (TypeScript)

### E2E Tests (Playwright)

Mocked by default — no backend needed. `make test-e2e` spins up its own
isolated Vite server (port 9999) so it never touches a real backend or a
dev server you have running on `:5173`. See `web/e2e/README.md`.

**First-time setup:** `npx playwright install chromium` (downloads the
browser binary — not pulled in by `bun install`).

Tests in `web/e2e/tests/*.spec.ts` cover user flows:
- Auth (login, logout, token refresh)
- Collection browsing (filters, pagination, search)
- Game detail (view, delete, collection assignment)
- Vibes management

**Why separate from unit tests?** E2E catches integration bugs (routing, state management, API contract mismatches) that unit tests miss.

## Quick Reference

| Scenario | Tool | File | Coverage |
|----------|------|------|----------|
| Handler + business logic | httptest + mocks | `*_test.go` | ~70-80% |
| External API interaction | httptest.Server | `*_test.go` | error cases |
| Config/utils | direct unit test | `*_test.go` | 80-100% |
| E2E user flow | Playwright | `e2e/tests/*.spec.ts` | happy path |

## Runnable Commands

```sh
# Run all Go tests verbosely with race detection
make test-v

# Check coverage (summary)
make test

# Check coverage (detailed per function)
go test -coverprofile=/tmp/cov.out ./services/api/...
go tool cover -func=/tmp/cov.out

# Run frontend E2E tests (mocked, no backend needed)
make test-e2e

# Quick smoke test before PR
make test-v && make lint
```

## Adding Tests

1. **Identify what to test:** handler behavior, error cases, edge cases (not every code path)
2. **Choose mocking strategy:**
   - Store interface mock → handler tests
   - httptest.Server → external API tests
   - Direct call → config/utils
3. **Name clearly:** `TestX_SuccessCase`, `TestX_MissingField`, `TestX_ServerError`
4. **Run before PR:** `make test-v` must pass, check coverage with `go tool cover`

## Coverage Gaps

Current state (66.8%):
- **High:** config (92%), apierr (100%), envelope (100%), httpx (99%), auth (78%), seed (79%)
- **Low:** jwt (60%), game (61%), profile (59%)
- **Missing:** jwt.NewVerifier (JWKS init), ensureAdminProfile (DB layer)

Focus on critical paths first (auth, config) before exhaustive coverage.
