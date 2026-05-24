# pkg/shared

Shared Go module imported by all mbgc microservices. Contains the contract
that keeps services consistent — do not break exported types without updating
all consumers.

## Module path

```
github.com/LuisMedinaG/mbgc/pkg/shared
```

## Packages

| Package | Contents |
|---|---|
| `envelope` | `Response[T]`, `ListResponse[T]`, `ErrorResponse` — JSON wire types + constructors |
| `apierr` | Sentinel errors (`ErrNotFound`, `ErrDuplicate`, …) + machine-readable codes + `Is*` helpers |
| `httpx` | HTTP middleware (`Logger`, `Recover`, `RequestID`, `CORS`, `SecurityHeaders`, `TrustGatewayHeaders`) + `WriteJSON` / `WriteError` + context accessors |

## Wire format

```json
// Single resource
{ "data": { ... } }

// Paginated list
{ "data": [...], "meta": { "page": 1, "limit": 20, "total": 142 } }

// Error
{ "error": { "code": "NOT_FOUND", "message": "game not found" } }
```

## Error mapping (apierr → HTTP)

| Sentinel | Code | Status |
|---|---|---|
| `ErrNotFound` | `NOT_FOUND` | 404 |
| `ErrDuplicate` | `DUPLICATE` | 409 |
| `ErrUnauthorized` / `ErrWrongPassword` | `UNAUTHORIZED` | 401 |
| `ErrForbidden` | `FORBIDDEN` | 403 |
| `ErrBadRequest` | `BAD_REQUEST` | 400 |
| `ErrValidation` | `VALIDATION_FAILED` | 422 |
| `ErrRateLimit` | `RATE_LIMIT_EXCEEDED` | 429 |
| unknown | `INTERNAL_ERROR` | 500 (logged, not leaked) |

## Key rules

- Never expose raw errors (DB, OS, network) to API consumers — wrap with a sentinel.
- Use `errors.Is` / `apierr.Is*` helpers for sentinel checks; wrap with `fmt.Errorf("%w", ...)` to add context.
- Middleware chain order: `SecurityHeaders → RequestID → Logger → Recover → TrustGatewayHeaders → router`.

## Updating this module

1. Bump the version tag (`vX.Y.Z`) after any breaking change.
2. Update `go.mod` in every consuming service (`go get github.com/LuisMedinaG/mbgc/pkg/shared@vX.Y.Z`).
3. Keep backwards-compatible additions in minor versions.

<claude-mem-context>
</claude-mem-context>
