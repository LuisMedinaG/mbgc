# pkg/shared

Shared Go module imported by `services/api` (and any future Go services in this monorepo). Contains the contract that keeps services consistent — do not break exported types without updating all consumers.

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
- Middleware chain order for `services/api`: `Logger → RequestID → Recover → SecurityHeaders → CORS → router` (auth middleware wraps individual routes, not the global chain).

## Updating this module

The monorepo uses `go.work` with a `replace` directive pointing all services to `./pkg/shared` — no version bump needed for local changes. After modifying this package:

1. Run `make tidy` in `services/api` to sync `go.sum`.
2. Run `make test-v` in `services/api` to catch breakage early.
3. If publishing externally (outside this monorepo): bump `vX.Y.Z`, then update `go get` in each consumer.

<claude-mem-context>
</claude-mem-context>
