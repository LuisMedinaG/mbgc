---
name: run-tests
description: Run Go unit tests for the backend. Use when asked to run tests or verify correctness.
---

# Run Tests

Each service has its own test suite. Run from the service directory.

## Go API commands

```sh
cd services/api
make test-v          # go test -v -race ./...  ← use before every PR
make tidy            # go mod tidy
make lint            # go vet ./...
```

## What's under test

| Package | Key coverage |
|---------|-------------|
| internal/apierr | error sentinels and codes |
| internal/httpx | response writing, middleware |
| internal/jwt | JWKS + HS256 verification |
| internal/catalog | game CRUD, filters, player aids |
| internal/importer | BGG sync, CSV import |
| internal/profile | profile management |

## Interpreting failures

- `FAIL` — read the test name and error; fix the root cause
- `pq: ...` / `pgx: ...` — DB error in test; check that the test DB is reachable and migrations ran
- `build failed` before any tests run — compile error; fix type/import first
- `race detected` — real concurrency bug; do not suppress with `-race=false`
