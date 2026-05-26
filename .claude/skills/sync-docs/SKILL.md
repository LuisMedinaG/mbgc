---
name: sync-docs
description: Update AGENTS.md and CLAUDE.md to reflect uncommitted changes or decisions made during a conversation. Use when asked to "sync docs", "update the agents file", "keep docs up to date", or after any architectural change, new convention, or environment update.
---

# Sync Docs

Keeps `AGENTS.md` and `CLAUDE.md` in sync with the current state of the codebase.

## When to use

- After adding a new service or changing the directory structure
- After changing a build command, migration command, or Makefile target
- After changing auth/JWT config, Supabase setup, or environment variables
- After establishing a new code convention during a session
- After updating infrastructure (new GCP service, Fly app, Cloudflare config)
- Before opening a PR that changes how any service is built or run

## What to update

### AGENTS.md — operational truth

Update the relevant section:

| Changed | Section |
|---------|---------|
| Build/test commands | `## Build & Test` |
| Supabase URLs, pooler ports, CLI commands | `## Supabase — Local vs Remote` |
| JWT algorithm, JWKS, secret handling | `## JWT / Auth (gateway)` |
| `pkg/shared` API surface | `## go.work Workspace` |
| New Go/TS convention established | `## Code Style (non-obvious rules)` |
| Branching rules, commit format | `## Git Workflow` |
| New cross-service constraint | `## Boundaries` |

### CLAUDE.md — architecture overview

Update only if structure changed:

| Changed | Section |
|---------|---------|
| New service added/removed | `## Directory Structure` |
| New routing path at gateway | `## Request Flow` |
| CI/CD workflow changed | `## CI/CD` |
| New infra resource | `## Infrastructure` |

### Per-service CLAUDE.md files

Each service has `services/<name>/CLAUDE.md`. Update when:
- New tables or schema changes in that service
- New API routes added
- New environment variables required

## How to sync

1. Read the current file: `ctx_read AGENTS.md`
2. Identify the stale section from the table above
3. Edit only the affected lines — don't rewrite whole sections
4. Verify no info is duplicated between AGENTS.md and CLAUDE.md

## What NOT to put in AGENTS.md

- File paths that change often (use service CLAUDE.md instead)
- Implementation details (use skill files or service CLAUDE.md)
- User-facing docs (belongs in README.md)
