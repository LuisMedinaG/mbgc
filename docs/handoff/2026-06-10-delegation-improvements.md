# Handoff: Delegation Improvements (#2 and #3)

Branch: `feature/profile-change-password`
Date: 2026-06-10
Status: Ready to implement — no blockers

---

## #2 — Extract `supabaseAuthClient` to `internal/supabase`

### Problem
`supabaseAuthClient` (token grant, refresh, user update) lives inside `auth/handler.go`.
It currently has 3 methods and will grow: any future package that needs to call Supabase
(e.g. admin operations, profile picture upload via Storage) must either duplicate the
HTTP client or import the auth package, creating an unnatural dependency.

### What to do
1. Create `services/api/internal/supabase/client.go`
2. Move `supabaseAuthClient` struct + all 3 methods (`doRequest`, `doRequestWithBearer`,
   `New`) into the new package as exported `Client` / `New(url, apiKey, httpClient)`
3. Update `auth/handler.go` to import and use `supabase.Client`
4. Update `auth/handler_test.go`: extract the fake Supabase server helper into a shared
   test helper, or keep inline (fine for now)

### Interface to expose
```go
// internal/supabase/client.go
type Client struct { ... }

func New(baseURL, apiKey string, hc *http.Client) *Client

// DoRequest: apikey only (token grant, refresh, logout)
func (c *Client) DoRequest(ctx context.Context, method, path string, body map[string]string) (int, []byte, error)

// DoRequestWithBearer: apikey + user JWT (PUT /auth/v1/user)
func (c *Client) DoRequestWithBearer(ctx context.Context, method, path string, body map[string]string, bearer string) (int, []byte, error)
```

### Why now?
The iOS app will likely add Sign in with Apple / Google via Supabase OAuth. That flow
requires calling Supabase from outside the auth package. Do this before adding OAuth.

---

## #3 — Centralize request validation

### Problem
Every handler does the same boilerplate:
```go
if req.Field == "" {
    httpx.WriteError(w, fmt.Errorf("%w: field is required", apierr.ErrBadRequest))
    return
}
if len(req.Password) < 8 {
    httpx.WriteError(w, fmt.Errorf("%w: ...", apierr.ErrBadRequest))
    return
}
```
This pattern is repeated in login, refresh, logout, changePassword, updateBGGUsername,
updateRulesURL. Adding iOS-specific endpoints will multiply it further.

### Option A — `go-playground/validator` (recommended)
```go
// usage in handler:
var req loginRequest
if err := httpx.DecodeValidate(r.Body, &req); err != nil {
    httpx.WriteError(w, err)  // already wrapped as ErrBadRequest
    return
}

// struct tag:
type changePasswordRequest struct {
    CurrentPassword string `json:"current_password" validate:"required"`
    NewPassword     string `json:"new_password"     validate:"required,min=8"`
}
```

**What to build:**
1. `go get github.com/go-playground/validator/v10`
2. Add `httpx.DecodeValidate[T any](body io.Reader, dst *T) error` to `pkg/shared/httpx/`
   — decodes JSON, runs `validate.Struct`, maps `ValidationErrors` to `apierr.ErrBadRequest`
3. Replace all `Decode + manual if checks` in handlers with `DecodeValidate`

### Option B — Lightweight custom helper (no new dep)
If adding a validator dep feels heavy, a simpler shared helper:
```go
// pkg/shared/httpx/request.go
func DecodeJSON[T any](body io.Reader, dst *T) error
func RequireFields(fields ...string) error   // variadic string pairs: ("field", value)
```
Less ergonomic but zero new dependencies.

### Files to update after implementing either option
- `internal/auth/handler.go` — login, refresh, logout, changePassword
- `internal/profile/handler.go` — updateBGGUsername, changePassword (if moved)
- `internal/game/handler.go` — updateRulesURL, createCollection
- `pkg/shared/httpx/` — add the helper

---

## Done on this branch
- `PUT /api/v1/auth/password` — closes `profile.CHANGE_PASSWORD` spec gap
- `ListGames` + `Discover` — squirrel replaces manual SQL building
