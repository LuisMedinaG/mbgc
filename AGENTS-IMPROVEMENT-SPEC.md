# AGENTS.md Improvement Spec

Audit date: 2026-05-01  
Branch: staging  
Files reviewed: `AGENTS.md`, `CLAUDE.md`, `go.work`, `set-deploy-secrets.sh`, `.devcontainer/devcontainer.json`

---

## Critical Fixes (blockers — agents will produce wrong output without these)

### 1. Resolve response envelope contradiction

`AGENTS.md` and `CLAUDE.md` define different error shapes:

| File | Error shape |
|---|---|
| `AGENTS.md` | `{ "error": { "code": "...", "message": "..." } }` |
| `CLAUDE.md` | `{ "error": "..." }` |

**Action:** Decide on one canonical shape and update both files to match. The structured form (`code` + `message`) is preferable for machine-readable error handling. Also verify against `mbgc-shared` sentinel error implementation and document the actual shape used there.

### 2. Resolve pagination contract contradiction

| File | Pagination shape |
|---|---|
| `AGENTS.md` | `{ "data": [...], "meta": { "page", "limit", "total" } }` |
| `CLAUDE.md` | top-level `total`, `page`, `per_page` |

**Action:** Audit actual API responses in `mbgc-game-service` and `mbgc-auth-service`. Pick one shape, update both files, and note which field name is used (`limit` vs `per_page`).

### 3. Correct the deploy target

Both files state deploy target is **Fly.io**, but `set-deploy-secrets.sh` configures **GCP Workload Identity** and GCP service accounts. The actual runtime is GCP (likely Cloud Run).

**Action:** Update the Services table and Infrastructure section to reflect the real deploy target. If both Fly.io and GCP are in use, document which services use which.

---

## Structural Additions (agents lack context to work effectively without these)

### 4. Add local development setup section

Agents need to know how to build and run services locally. Add a section covering:

- Go workspace usage: `go work sync`, building individual services (`go build ./...` from service dir)
- Required environment variables per service (or reference to `.env.example` files that should be created)
- How to run the monolith locally
- How to run `mbgc-web` locally (package manager, dev server command)

### 5. Add test strategy section

No test guidance exists. Add:

- Go: `go test ./...` from workspace root or per-service
- TypeScript: test runner and command for `mbgc-web`
- Whether integration tests exist and how to run them
- Minimum expectations (e.g., "all PRs must pass `go test ./...`")

### 6. Add coding conventions section

Add a brief section covering:

- Go: `gofmt`/`goimports` required, linter (`golangci-lint`) config location if it exists
- TypeScript: formatter (Prettier/ESLint), config location
- Naming: package names, exported vs unexported, file naming conventions
- Error handling: always wrap with `fmt.Errorf("context: %w", err)`, use sentinel errors from `mbgc-shared`

### 7. Document service-to-service authentication

The gateway validates JWTs from clients, but how services authenticate to each other (e.g., game-service calling auth-service) is undocumented. Add:

- Whether internal calls are unauthenticated (trusted network) or use service tokens
- Any shared secrets or mTLS setup

### 8. Add migration status tracker

The monolith decomposition is in progress. Add a section or table showing:

- Which features/domains have been migrated to microservices
- Which are still in the monolith only
- Which are duplicated (monolith + service coexist)
- Target end state

### 9. Create `dev` branch

The branching strategy requires `feature/* → dev → staging → main` but `dev` does not exist remotely.

**Action:** Create `dev` branch from `main` and push it. Update AGENTS.md to note that `dev` is the integration branch for active development.

---

## Agent Tooling Additions (improve agent workflow quality)

### 10. Add PR template

Create `.github/pull_request_template.md` with:

```markdown
## What
<!-- One sentence: what does this change do? -->

## Why
<!-- Motivation or issue reference -->

## Service(s) affected
<!-- List affected services/repos -->

## Checklist
- [ ] `go test ./...` passes
- [ ] No raw DB errors exposed to clients
- [ ] Response envelope matches documented shape
```

### 11. Create `.ona/skills/` directory with reusable workflows

Add skill files for common agent tasks:

- `add-api-endpoint.md` — steps for adding a new endpoint (handler, route registration, tests, envelope compliance)
- `add-service.md` — steps for scaffolding a new microservice (go.mod, Dockerfile, gateway route, Terraform resource)
- `db-migration.md` — steps for schema changes (migration file, rollback, test data)

### 12. Document `mbgc-infra` usage

Add a section explaining:

- What Terraform manages (Fly apps / GCP services, Cloudflare Pages, Supabase project)
- How to plan and apply changes (`terraform plan`, `terraform apply`)
- Whether infra changes require a PR or can be applied directly
- State backend location

---

## File Hygiene

### 13. Merge or diff-lock `AGENTS.md` and `CLAUDE.md`

Both files contain nearly identical content but with contradictions (items 1 and 2 above). Options:

- **Option A:** Make `CLAUDE.md` a symlink or include directive pointing to `AGENTS.md` (single source of truth)
- **Option B:** Keep both but add a header to each: `# Source of truth: AGENTS.md — do not edit CLAUDE.md directly`
- **Option C:** Delete `CLAUDE.md` and rely solely on `AGENTS.md`

Recommended: Option A or C. Having two files with diverging content will cause agents to produce inconsistent behavior depending on which file they read.

### 14. Add `myboardgamecollection` to `go.work`

The monolith is a Go service but is absent from `go.work`. If it shares any modules with the workspace, add it. If it's intentionally isolated, document why.

---

## Priority Order

| Priority | Item | Reason |
|---|---|---|
| P0 | 1, 2, 3 | Agents produce wrong output today |
| P1 | 4, 5, 9 | Agents cannot build/test/branch correctly |
| P2 | 6, 7, 10 | Agents produce inconsistent code quality |
| P3 | 8, 11, 12, 13, 14 | Useful context, not immediately blocking |
