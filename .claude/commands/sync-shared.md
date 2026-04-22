---
description: Bump the mbgc-shared dependency version across every Go service and verify each one still builds.
argument-hint: [version-or-pseudo-version]
---

Bump `mbgc-shared` to version `$ARGUMENTS` across every Go service that depends on it (`mbgc-gateway`, `mbgc-auth-service`, `mbgc-game-service`, `mbgc-importer-service`, and `myboardgamecollection` if it imports shared).

If `$ARGUMENTS` is empty, use the current HEAD of the local `mbgc-shared` checkout (derive the pseudo-version from `git log -1`).

Steps:
1. In each service directory, run `go get github.com/<org>/mbgc-shared@<version>` and `go mod tidy`.
2. At the workspace root, run `go work sync`.
3. In each service, run `go build ./...` and `go vet ./...`. Report pass/fail per service.
4. Summarize which `go.mod` files changed and what the new require line looks like.

Stop and surface the failure if any service fails to build — do NOT silently skip. Do not commit; leave the changes for the user to review.
