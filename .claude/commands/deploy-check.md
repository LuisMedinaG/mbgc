---
description: Pre-deploy sanity check across the workspace — build, vet, tests, tf validate. Does NOT deploy.
argument-hint: [service-name-or-all]
---

Run a pre-deploy sanity check for `$ARGUMENTS` (or all services if empty).

For each in-scope Go service:
- `go build ./...`
- `go vet ./...`
- `go test ./...` (skip integration tests that need external creds — note which are skipped)

For `mbgc-web` (if in scope): `npx tsc --noEmit` and `npm test -- --run` (or the project's non-watch form).

For `mbgc-infra` (if in scope): `terraform fmt -check` and `terraform validate`. NEVER `terraform plan` against a live backend without explicit user confirmation; NEVER `apply`.

Report a single per-target pass/fail table with the first failing line of output for anything that fails. Do not attempt fixes — this is a gate, not a repair step.
