---
description: Summarize per-service git state, branch, and dirty files across the workspace.
---

For each subdirectory in this meta-workspace that is itself a git repo — `mbgc-shared`, `mbgc-gateway`, `mbgc-auth-service`, `mbgc-game-service`, `mbgc-importer-service`, `mbgc-web`, `mbgc-infra`, `myboardgamecollection` — report:

- current branch
- whether the working tree is clean
- commits ahead/behind its upstream
- the most recent commit (hash + subject)

Skip any subdir that isn't populated. Present the result as a single table, one row per service. Keep it under 40 lines. Do not make any changes.
