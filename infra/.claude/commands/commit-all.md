For each repo under /Users/lumedina/Documents/Projects/mbgc — in this order:
myboardgamecollection, mbgc-gateway, mbgc-auth-service, mbgc-game-service,
mbgc-importer-service, mbgc-importer-service, mbgc-web, mbgc-shared, mbgc-infra —
do the following:

1. Run `git -C <repo_path> status --short` to check for changes.
2. If there are no changes (clean working tree), skip the repo and note it was skipped.
3. If there are changes, run:
   - `git -C <repo_path> add -A`
   - `git -C <repo_path> commit -m "$ARGUMENTS"`
   - `git -C <repo_path> push`
4. Report success or failure for each repo.

The commit message is: $ARGUMENTS

After processing all repos, print a one-line summary: how many were committed/pushed vs skipped vs failed.

Important:
- Never skip the status check — don't commit clean repos.
- If push fails on a repo, report the error and continue with the next repo.
- Use the exact path /Users/lumedina/Documents/Projects/mbgc/<repo> for each.
