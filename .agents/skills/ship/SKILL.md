---
name: ship
description: Full ship workflow — test, commit, push, open PR to dev. Use when a feature is ready to ship.
---

# Ship

## Current branch state

- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Commits ahead of dev: !`git log origin/dev..HEAD --oneline`

## Workflow

### 1. Tests

Run from the service directory for every changed service:

```sh
make test-v
```

Fix all failures before continuing.

### 2. Commit

Ask the user to review the diff before committing. Per AGENTS.md: always ask before committing.

```sh
git add <specific files>   # never git add -A blindly
git commit -m "type: short description"
```

Types: `feat` | `fix` | `refactor` | `docs` | `chore` | `test`  
Subject: imperative, ≤50 chars.

### 3. Push

Only push when user explicitly says "push".

```sh
git push -u origin <branch>
```

Never push directly to `main` or `staging`.

### 4. PR to dev

```sh
gh pr create --base dev --title "type: description" --body "$(cat <<'EOF'
## Summary
- <what changed>
- <why>

## Test plan
- [ ] `make test-v` passes in changed service(s)
- [ ] Manually verified <key flow>
- [ ] No secrets or sensitive data in commit
EOF
)"
```

## Branching rules

```
feature/*  →  dev  →  staging  →  main
```

- `feature/*` → `dev`: direct push is OK
- `dev` → `staging`: PR required
- `staging` → `main`: PR required
- Never push directly to `main` or `staging`

## Checklist

- [ ] `make test-v` passes in all changed services
- [ ] User reviewed diff before commit
- [ ] PR targets `dev` (not `main` or `staging`)
- [ ] No `.env` files or secrets in commit
- [ ] `supabase db push` NOT run unless explicitly asked (writes to production)
