---
name: run-tests
description: Run Go unit tests for the backend. Use when asked to run tests or verify correctness.
---

# Run Tests

Each service has its own test suite. Run from the service directory.

## Per-service commands

```sh
cd services/<name>   # gateway | auth | game | importer
make test            # go test ./...
make test-v          # go test -v -race ./...  ← use before every PR
make lint            # go vet ./...
```

## Run all services at once

```sh
for svc in gateway auth game importer; do
  echo "=== $svc ===" && make -C services/$svc test
done
```

## What's under test

| Service | Key packages |
|---------|-------------|
| gateway | JWT validation (JWKS + HS256 fallback), middleware chain |
| auth    | profile store, BGG username handling |
| game    | filter logic, store queries |
| importer | BGG HTTP client, sync logic |

Shared library (`pkg/shared`) has its own tests — run `make test-v` there when touching exported types.

## Before every PR

```sh
make test-v   # from the changed service directory
```

For changes to `pkg/shared` run `make test-v` in **every** consuming service (gateway, auth, game, importer).

## Interpreting failures

- `FAIL` — read the test name and error; fix the root cause
- `pq: ...` / `pgx: ...` — DB error in test; check that the test DB is reachable and migrations ran
- `build failed` before any tests run — compile error; fix type/import first
- `race detected` — real concurrency bug; do not suppress with `-race=false`
