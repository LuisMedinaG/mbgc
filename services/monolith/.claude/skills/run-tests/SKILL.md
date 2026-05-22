---
name: run-tests
description: Run Go unit tests for the backend. Use when asked to run tests or verify correctness.
---

# Run Tests

The backend is Go-only. The React frontend (`mbgc-web`) has its own test suite in that repo.

## Commands

```sh
make test        # all tests
make test-v      # verbose — shows each test name
make cover       # per-package coverage %
make cover-html  # HTML coverage report (writes /tmp/coverage.html)
make vet         # go vet ./...
make check       # build + test + vet
```

## Packages under test

- `shared/httpx` — auth middleware, JWT, rate limiting
- `shared/db` — schema + idempotent migrations
- `services/games` — filter logic (`filter_test.go`)

## Before shipping

At minimum:

```sh
make test
```

For changes that touch auth, JWT, or the DB schema, run `make check` so `go vet` also runs.

## Interpreting failures

- `FAIL` in Go output — read the test name and error, fix the root cause
- `UNIQUE constraint` in tests — test isolation issue; use a fresh DB or unique IDs per test
- `build failed` before any test runs — compile error; fix the type or import first
