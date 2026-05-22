---
name: adding-middleware
description: Adds, modifies, or reorders HTTP middleware in this Go service — the httpx.Chain pattern, RequireJWT/MethodGuard/CORS/SecurityHeaders/RateLimit wrappers, context identity helpers, and the pub/protected factories in main.go. Use when the user asks to add auth to a route, rate-limit an endpoint, add a security header, change CORS, or wire a new piece of middleware.
---

# Adding middleware

All middleware lives in `shared/httpx/httpx.go`. Route-level middleware is composed per-handler in `main.go` via the `pub`/`protected` factories; app-wide middleware wraps the mux in the outer `httpx.Chain` call.

## Middleware signature

```go
type Middleware func(http.Handler) http.Handler
```

A new middleware is a function that closes over its config and returns a `Middleware`. Keep config in the outer closure; never mutate request-scoped state outside the handler.

```go
func MyMiddleware(opt Opt) Middleware {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            // 1. pre-checks — short-circuit with httpx.WriteJSONError on failure
            // 2. enrich r.Context() if you're attaching identity/metadata
            // 3. next.ServeHTTP(w, r.WithContext(ctx))
        })
    }
}
```

## Execution order

`httpx.Chain(h, A, B, C)` produces `A(B(C(h)))` — A runs first, C runs last before the handler. This is the intuitive left-to-right order. When adding a new middleware to an existing chain, put it where its dependencies are satisfied:

- `RequireJWT` must come **after** anything that needs the raw `Authorization` header but **before** handlers that call `UserIDFromContext`.
- `MethodGuard` belongs first on per-route chains so wrong-method requests don't cost an auth check.
- `SecurityHeaders` and `CORS` wrap the entire mux so preflight (`OPTIONS`) is handled before routing.

## Route-level middleware (main.go)

Per-route chains go through two factories defined inline in `main.go`:

```go
pub := func(method string, hf http.HandlerFunc) http.Handler {
    return httpx.Chain(hf, httpx.MethodGuard(method))
}
protected := func(method string, hf http.HandlerFunc) http.Handler {
    return httpx.Chain(hf, httpx.MethodGuard(method), httpx.RequireJWT(jwtSecret))
}
```

- `pub(...)` — method-guarded, no auth. Login / refresh / logout only.
- `protected(...)` — method-guarded + JWT-required. Every other `/api/v1/` route.

Don't hand-roll chains at the route site; extend the factories if you need a new default. For a route that needs extra middleware (e.g. rate limiting on login), wrap the handler before passing to `pub`:

```go
mux.Handle("POST /api/v1/auth/login",
    pub(http.MethodPost, httpx.Chain(http.HandlerFunc(authH.Login), httpx.RateLimit(loginLimiter)).ServeHTTP))
```

Or — cleaner — add a new factory (`protectedRateLimited`, etc.) if the pattern repeats.

## Global middleware (mux wrapper)

Wrap the mux once at server construction:

```go
Handler: httpx.Chain(mux,
    httpx.SecurityHeaders(),
    httpx.CORS(reactOrigin),
),
```

Order here is outermost-first. `SecurityHeaders` wraps `CORS` so the CSP/HSTS headers apply even to preflight responses. If you add a new global middleware, decide whether it should run on every request (global) or only authenticated ones (per-route).

## Identity context

When a middleware needs to attach identity, use the provided helpers:

```go
ctx := httpx.SetUser(r.Context(), userID, username, isAdmin)
next.ServeHTTP(w, r.WithContext(ctx))
```

Downstream handlers read it with:

```go
userID, ok := httpx.UserIDFromContext(r.Context())
username    := httpx.UsernameFromContext(r.Context())
isAdmin     := httpx.IsAdminFromContext(r.Context())
```

Don't invent new context keys for user identity — add fields to `SetUser` / add a new getter if genuinely needed. Keep context keys inside `httpx` (`contextKey` is unexported) so no collisions are possible.

## Error responses inside middleware

Always JSON. Use `httpx.WriteJSONError(w, status, msg)`:

```go
httpx.WriteJSONError(w, http.StatusUnauthorized, "unauthorized")
return
```

Don't fall back to `http.Error` — the React client expects `{"error": "..."}`. The one existing exception is `MethodGuard` which returns `text/plain` for 405s; that's fine because method-mismatch is developer error, not a user-facing case.

## Rate limiting

`LoginLimiter` is a sliding-window per-IP counter. Construct once, share across handlers:

```go
loginLimiter := httpx.NewLoginLimiter(5, time.Minute)
```

Two integration patterns:

- **Middleware** — `httpx.RateLimit(limiter)` rejects at the edge. Good for pure throttling.
- **Handler-level** — call `limiter.Allow(ip)` / `limiter.Record(ip)` inside the handler so failed attempts increment but successful ones don't. Used by the login flow.

Start a cleanup goroutine in `main.go`:

```go
go func() {
    t := time.NewTicker(time.Hour)
    defer t.Stop()
    for {
        select {
        case <-t.C: loginLimiter.Cleanup()
        case <-ctx.Done(): return
        }
    }
}()
```

Honor the shutdown context (`ctx.Done()`) — don't leak goroutines past server shutdown.

Extract the client IP via `httpx.ClientIP(r)` — it honors `X-Forwarded-For` (Fly sets it), not `r.RemoteAddr`.

## CORS

`httpx.CORS` reads a comma-separated origin list (`REACT_ORIGIN` env). A single `"*"` allows all origins; anything else is an exact-match allowlist. When adding a new frontend origin, change the env var, not the middleware — avoid hard-coded hosts.

## Verification

```sh
make test    # jwt_test.go, csrf_test.go, ratelimit_test.go cover middleware
make build   # catches signature changes
# Manual:
curl -I localhost:8080/api/v1/ping          # expect 401 without Authorization
curl -I -H "Authorization: Bearer bad" localhost:8080/api/v1/ping  # 401
# Preflight:
curl -i -X OPTIONS -H "Origin: https://lumedina.dev" localhost:8080/api/v1/games
```
