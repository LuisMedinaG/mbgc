# pkg/shared

Shared Go module used by `services/api` and any future Go services in this monorepo.

## Packages

| Package | Purpose |
|---------|--------|
| `envelope` | Standard JSON response wrappers (`Response`, `ListResponse`, `ErrorResponse`) |
| `apierr` | Sentinel errors and machine-readable error codes |
| `httpx` | HTTP middleware (`Logger`, `Recover`, `RequestID`, `CORS`, `SecurityHeaders`, `RateLimiter`, `LimitBodySize`) and context helpers |

## Wire format

```json
// Single resource
{"data": {"id": "...", "name": "..."}}

// Paginated list
{"data": [...], "meta": {"page": 1, "limit": 20, "total": 142}}

// Error
{"error": {"code": "NOT_FOUND", "message": "game not found"}}

// Validation error (with field details)
{"error": {"code": "VALIDATION_FAILED", "message": "invalid input", "details": {"name": "required"}}}
```

## Error codes

| Code | HTTP Status | Sentinel error |
|------|-------------|----------------|
| `BAD_REQUEST` | 400 | `apierr.ErrBadRequest` |
| `UNAUTHORIZED` | 401 | `apierr.ErrUnauthorized`, `apierr.ErrWrongPassword` |
| `FORBIDDEN` | 403 | `apierr.ErrForbidden` |
| `NOT_FOUND` | 404 | `apierr.ErrNotFound` |
| `CONFLICT` / `DUPLICATE` | 409 | `apierr.ErrDuplicate` |
| `VALIDATION_FAILED` | 422 | — (handlers build manually with details) |
| `RATE_LIMIT_EXCEEDED` | 429 | `apierr.ErrRateLimit` |
| `INTERNAL_ERROR` | 500 | any unrecognised error |

## Middleware stack (recommended order)

```go
httpx.Chain(router,
    httpx.Logger,          // outermost — logs every request
    httpx.RequestID,       // injects X-Request-ID
    httpx.Recover,         // catches panics
    httpx.SecurityHeaders, // security headers
    httpx.CORS(origins),   // CORS preflight
    // auth middleware (your jwt.Verifier.RequireAuth) wraps individual routes
)
```

## Usage

```go
import (
    "github.com/LuisMedinaG/mbgc/pkg/shared/apierr"
    "github.com/LuisMedinaG/mbgc/pkg/shared/envelope"
    "github.com/LuisMedinaG/mbgc/pkg/shared/httpx"
)

func (h *Handler) GetGame(w http.ResponseWriter, r *http.Request) {
    userID, ok := httpx.UserIDFromContext(r.Context())
    if !ok {
        httpx.WriteError(w, apierr.ErrUnauthorized)
        return
    }
    game, err := h.svc.GetGame(r.Context(), id, userID)
    if err != nil {
        httpx.WriteError(w, err) // maps sentinel → HTTP status + error code
        return
    }
    httpx.WriteJSON(w, http.StatusOK, envelope.New(game))
}
```

## Local development

In consuming services, use a `replace` directive to point at your local checkout:

```go
// go.mod
replace github.com/LuisMedinaG/mbgc/pkg/shared => ../pkg/shared
```
