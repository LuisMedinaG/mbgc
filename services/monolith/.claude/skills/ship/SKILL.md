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

```sh
make test
```

Fix any failures before continuing. Do not skip.

### 2. Commit

Ask the user to review the diff (`git diff --staged` or `git status`) before committing. Per CLAUDE.md: always ask before committing.

Use the `/commit` skill, or:

```sh
git add <specific files>   # never git add -A blindly
git commit -m "type: description"
```

Commit types: `feat` | `fix` | `refactor` | `docs` | `chore` | `test`

### 3. Push

Only push when the user explicitly says "push" (see CLAUDE.md rules).

```sh
git push -u origin <branch>
```

Never push directly to `main` or `staging`. Feature branches push to `feature/*`; `dev` accepts direct pushes.

### 4. PR to dev

```sh
gh pr create --base dev --title "type: description" --body "$(cat <<'EOF'
## Summary
- <what changed>
- <why>

## Test plan
- [ ] `make test` passes
- [ ] Manually verified <key flow>
EOF
)"
```

## Branching rules

```
feature/*  →  dev  →  (PR to) staging  →  (PR to) main
```

- `feature/*` → `dev`: direct push OK
- `dev` → `staging`: PR required
- `staging` → `main`: PR required
- Never admin-bypass GitHub rulesets

## Checklist

- [ ] `make test` passes
- [ ] User reviewed diff before commit
- [ ] PR targets `dev` (not `main` or `staging`)
- [ ] No secrets or sensitive data in commit
