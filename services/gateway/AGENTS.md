# AGENTS.md — services/gateway

API gateway: single ingress point. Validates JWTs and reverse-proxies to upstream services. No business logic, no DB.

## Commands

```sh
make dev      # go run ./cmd/server; loads .env; listens on :8000
make test-v   # go test -v -race ./...
make lint     # go vet ./...
```

## Adding a route

1. Add prefix → upstream URL mapping in `cmd/server/main.go`
2. Update the routing table in `CLAUDE.md`
3. The gateway extracts JWT claims and forwards `X-User-ID`, `X-Username`, `X-Is-Admin` — upstream services call `httpx.UserIDFromContext` to read these; they never re-validate the token

## Boundaries

**Never:**
- Add business logic or DB access
- Issue or refresh tokens (that is Supabase / services/auth)
- Create pass-through routes that skip JWT validation
- Add CORS headers in upstream services — CORS is configured here only

**Ask first:**
- Changing JWT validation logic or the forwarded header names (all downstream services depend on them)
- Adding a new public (unauthenticated) endpoint
