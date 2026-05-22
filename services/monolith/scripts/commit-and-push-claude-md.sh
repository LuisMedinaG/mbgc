#!/usr/bin/env bash
# Commits and pushes the CLAUDE.md files created by setup-mbgc-claude-md.sh
# to each service repo.
#
# Usage:
#   bash ~/Documents/Projects/mbgc/myboardgamecollection/scripts/commit-and-push-claude-md.sh
#
# Each repo's CLAUDE.md is committed to its current branch and pushed to origin.

set -euo pipefail

ROOT="$HOME/Documents/Projects/mbgc"

repos=(
  "mbgc-shared"
  "mbgc-gateway"
  "mbgc-auth-service"
  "mbgc-game-service"
  "mbgc-importer-service"
  "mbgc-web"
  "mbgc-infra"
  "myboardgamecollection"
)

echo "==> committing and pushing CLAUDE.md to all repos"
echo ""

for repo in "${repos[@]}"; do
  repo_path="$ROOT/$repo"

  if [ ! -d "$repo_path/.git" ]; then
    echo "⊘   $repo — not a git repo, skipping"
    continue
  fi

  if [ ! -f "$repo_path/CLAUDE.md" ]; then
    echo "⊘   $repo — CLAUDE.md does not exist, skipping"
    continue
  fi

  echo "→   $repo"

  cd "$repo_path"

  # Check if CLAUDE.md is already committed
  if git ls-files --error-unmatch CLAUDE.md &>/dev/null; then
    echo "    CLAUDE.md already committed, skipping"
    continue
  fi

  # Add, commit, and push
  git add CLAUDE.md
  git commit -m "docs: add CLAUDE.md with service context"
  git push -u origin HEAD

  echo "    ✓ committed and pushed"
  echo ""
done

echo "Done."
