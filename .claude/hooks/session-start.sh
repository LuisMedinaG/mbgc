#!/bin/bash
# SessionStart hook for the mbgc meta-workspace.
#
# Each service lives in its own repo and is cloned into a sibling directory
# here. Those subdirs are empty placeholders until the user checks them out.
# This hook:
#   1) reports which subrepos are populated,
#   2) syncs Go workspace deps for whichever Go services are present,
#   3) installs npm deps for mbgc-web if present,
# so tests and linters work immediately inside each subrepo.
#
# Safe to run repeatedly — all steps are idempotent.

set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

GO_SERVICES=(mbgc-shared mbgc-gateway mbgc-auth-service mbgc-game-service mbgc-importer-service myboardgamecollection)
any_go_populated=0

echo "mbgc workspace — subrepo status:"
for d in "${GO_SERVICES[@]}" mbgc-web mbgc-infra; do
  if [ -f "$d/go.mod" ] || [ -f "$d/package.json" ] || [ -f "$d/main.tf" ]; then
    echo "  [populated] $d"
    case "$d" in
      mbgc-web|mbgc-infra) ;;
      *) any_go_populated=1 ;;
    esac
  elif [ -n "$(ls -A "$d" 2>/dev/null || true)" ]; then
    echo "  [present]   $d"
  else
    echo "  [empty]     $d  (clone the repo into this directory to work on it)"
  fi
done

if [ "$any_go_populated" = "1" ] && command -v go >/dev/null 2>&1; then
  echo "Syncing Go workspace…"
  go work sync || echo "  go work sync failed (non-fatal)"
  for d in "${GO_SERVICES[@]}"; do
    if [ -f "$d/go.mod" ]; then
      (cd "$d" && go mod download) || echo "  go mod download failed in $d (non-fatal)"
    fi
  done
fi

if [ -f "mbgc-web/package.json" ] && command -v npm >/dev/null 2>&1; then
  echo "Installing mbgc-web deps…"
  (cd mbgc-web && npm install --no-audit --no-fund --prefer-offline) || echo "  npm install failed (non-fatal)"
fi

echo "Done."
