#!/bin/sh
# infra/scripts/lib/common.sh
#
# Shared helpers for bootstrap scripts — source this file, do not execute it.
# Callers must set $REPO before calling set_gh_secret or sync_secrets.

# ── Core ───────────────────────────────────────────────────────────────────────

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

check_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed"
}

# ── Prompts ────────────────────────────────────────────────────────────────────

# prompt_value VAR "Description" env_val [default]
#   env_val non-empty  → accept silently (already configured)
#   default non-empty  → show prompt with [default]; Enter accepts it
#   both empty         → require user input
prompt_value() {
  _var="$1" _desc="$2" _env_val="${3:-}" _default="${4:-}"
  if [ -n "$_env_val" ]; then
    eval "${_var}=\"\${_env_val}\""
    printf '  ✓ %s\n' "$_desc"
    return
  fi
  if [ -n "$_default" ]; then
    printf '  %s [%s]: ' "$_desc" "$_default"
  else
    printf '  %s: ' "$_desc"
  fi
  read -r _input
  if [ -z "$_input" ] && [ -n "$_default" ]; then
    eval "${_var}=\"\${_default}\""
  elif [ -n "$_input" ]; then
    eval "${_var}=\"\${_input}\""
  else
    die "$_desc is required"
  fi
}

# prompt_secret VAR "Description" env_val
#   env_val non-empty  → accept silently
#   empty              → prompt with echo disabled; restores echo on SIGINT
prompt_secret() {
  _var="$1" _desc="$2" _env_val="${3:-}"
  if [ -n "$_env_val" ]; then
    eval "${_var}=\"\${_env_val}\""
    printf '  ✓ %s\n' "$_desc"
    return
  fi
  printf '  %s: ' "$_desc"
  trap 'stty echo 2>/dev/null; printf "\n"; exit 1' INT
  stty -echo 2>/dev/null || true
  read -r _input
  stty echo 2>/dev/null || true
  trap - INT
  printf '\n'
  [ -n "$_input" ] || die "$_desc is required"
  eval "${_var}=\"\${_input}\""
}

# ── GitHub secrets ─────────────────────────────────────────────────────────────

# set_gh_secret NAME value  (requires $REPO set by caller)
set_gh_secret() {
  printf '%s' "$2" | gh secret set "$1" --repo "$REPO"
  printf '  ✓ %s\n' "$1"
}

# sync_secrets "label" NAME value [NAME value ...]
sync_secrets() {
  _label="$1"; shift
  printf '\n── %s ──\n' "$_label"
  while [ $# -ge 2 ]; do
    set_gh_secret "$1" "$2"
    shift 2
  done
}
