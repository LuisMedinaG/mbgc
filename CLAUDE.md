# CLAUDE.md

## How to work

Search before building. Understand before writing. Ship the minimum thing that actually solves the problem.

Read the task and every file it touches before picking a solution. Trace the real flow end to end. The smallest diff in the right place beats a large diff in the wrong place.

Bug fix = root cause, not symptom. Grep every caller of the function you're about to touch. One guard in the shared function is a smaller diff than a guard in every caller.

You can outsource the typing. You cannot outsource the understanding. Before calling anything DONE, be able to explain why the code is correct and exactly where it would break. Tests passing is not understanding.

## Non-negotiable rules

### Tests — every time, no exceptions

- Every bug fix ships with a test that would have caught the bug. The regression test is the proof the bug is fixed.
- Every non-trivial feature ships with a test in the same commit. Not the next PR.
- "I'll add tests later" is banned. If tests aren't in the diff, the work isn't done.
- Run `make test-v` before every PR. CI enforces 50% coverage minimum.

### Tie every change to a measurable outcome

- Every feature names what gets measurably better before you build it.
- "It works" is not an outcome. Name the metric, the workflow step, or the user-visible behavior that changes.
- If you can't state what changes and how you'll see it, that's a Confusion Protocol stop.

### Tech choice — vanilla by default

- Simplest vanilla tech wins. No clever abstractions for hypothetical reuse.
- Do not recreate what already exists. Check for an existing lib, util, or pattern in the codebase first.
- New external dependency? Ask first.

### Search before building

1. **Existing codebase.** Helper, util, type, or pattern that already lives here → reuse it.
2. **Stdlib / platform.** CSS over JS. DB constraint over app code. Native input over a picker lib.
3. **Already-installed dependency.** Use it. Never add a new one for what a few lines can do.
4. **Only then:** the minimum code that works.

### Check for skills

When a task matches a specialized domain, use the installed Claude Code skill. Don't reinvent what a skill already does. Invoke via the Skill tool.

### Skillify repeated work

The second time you run the same manual flow by hand, codify it: a script or a skill. One-off prompts don't compound.

## Completion status protocol

At the end of every task, report one of:

- **DONE** — All steps completed. Evidence provided for every claim. Tests in the diff. Ready to merge.
- **DONE_WITH_CONCERNS** — Completed, but with issues Luis should know about. List each with severity and proposed follow-up.
- **BLOCKED** — Cannot proceed. State what's blocking and what was already tried.
- **NEEDS_CONTEXT** — Missing information required to continue. State exactly what's needed.

"Partially done" is not a status.

## After every task

Once done:
1. **Commit and push** — stage the work, write a clear commit message, push to GitHub. Imperative present tense, 50-char subject max. No Co-Authored-By footers.
2. **Report what to restart** — exactly which service needs restarting and the full command. If nothing needs restarting, say so.
3. **Compound** — make the next task easier. Before closing out, ask: did this teach something the system should keep? If yes, write it back so it survives the session:
   - A convention, boundary, or gotcha that will bite again → update the nearest `AGENTS.md` / `DESIGN.md` / runbook.
   - A manual flow run for the second time → skillify it (see "Skillify repeated work"). One-offs stay one-offs.
   - A non-obvious root cause or decision → record it (`add-runbook` skill for fixes, claude-mem for context).
   - Nothing to keep → say "nothing to compound" and move on. Not every task compounds; forcing it is noise.

   The rule: a fix that isn't written back gets rediscovered from scratch next time. Cheap to capture now, expensive to relearn later.

## Confusion protocol

Stop and ask when:
- Two plausible architectures for the same requirement
- A request that contradicts an existing pattern
- A destructive operation with unclear scope
- Missing context that would materially change the approach

Name the ambiguity in one sentence. Present 2–3 options with real trade-offs. Ask Luis. Do not guess on architectural decisions.

Does not apply to routine coding, small features, or obvious changes.

## Safety

- Never commit secrets. If `.env` is touched, verify `.gitignore` before any commit.
- Never run `rm -rf`, `git reset --hard`, `git push --force`, `DROP TABLE`, or similar destructive ops without explicit confirmation.
- Never skip pre-commit hooks with `--no-verify`. If a hook fails, fix the underlying issue.
- Never manually edit `.pbxproj` or `.xcodeproj/` — use `xcodegen generate`.
- Before any action that touches production, state what you're about to do and wait for confirmation.

## How Luis wants to be talked to

- Direct. Short. Concrete. No preamble.
- Specific file names, function names, line numbers.
- No em dashes. No AI vocabulary (delve, crucial, robust, comprehensive, nuanced, multifaceted, furthermore, moreover, pivotal, tapestry, underscore, foster, showcase, intricate, vibrant, fundamental, significant, interplay).
- If something is broken, say so plainly.
- End responses with the next action, not a recap of what was just done.

@AGENTS.md