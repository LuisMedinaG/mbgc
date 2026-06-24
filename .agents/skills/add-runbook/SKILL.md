---
name: add-runbook
description: Add a troubleshooting entry to the runbook. Use when the user hits and fixes an error to document it for future reference, or when asked to "document this issue" or "add to runbook".
---

# Add Runbook Entry

Captures troubleshooting fixes so nobody (human or agent) has to debug the same issue twice.

## When to use

- After fixing a non-trivial error (build, deploy, infra, db, auth)
- User says "document this", "add to runbook", "remember this fix"
- Agent self-triggers: after resolving an error that required >2 investigation steps

## Entry format

Files go in `docs/runbook/<category>/<kebab-case-name>.md`. Required sections:

```markdown
# <Title — human-readable one-liner>

## Symptoms
- Error message copy-pasted verbatim
- Log output, exit codes, behavioral clues

## Root cause
One sentence. What actually broke and why.

## Fix
Immediate steps to resolve. Commands only — no exposition.

## Prevention
Long-term change that stops recurrence. Applies to config/CI/lint/guard.

## Related
- `path/to/file:line` — the code or config involved
- `docs/runbook/...` — linked prior issue if this is a variant
```

### Rules

- **Concise.** Each section ≤3 lines. Commands, not paragraphs.
- **Copy-paste ready.** Error text must match what `rg`/`grep` would find.
- **Atomic.** One distinct cause per file. Link variants via Related.
- **No speculation.** Only document what was confirmed — skip "might also be...".

## Categories

| Category | Directory | Examples |
|---|---|---|
| Cloud Run | `docs/runbook/cloud-run/` | container failed to start, missing env vars |
| Terraform | `docs/runbook/terraform/` | drift, state lock, provider errors |
| Supabase | `docs/runbook/supabase/` | link unauthorized, connection pooling, migration errors |
| CI/CD | `docs/runbook/ci-cd/` | deploy failure, WIF auth, lint errors |

Create new category directories as needed.

## Process

1. Confirm the fix works
2. Identify the category from the table above
3. Create `docs/runbook/<category>/<name>.md` using the format above
4. Mention the runbook entry in AGENTS.md sync-docs if the issue is infra-level (optional)
