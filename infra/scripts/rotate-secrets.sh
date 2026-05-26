#!/bin/sh
# rotate-secrets.sh — Rotate one or all mbgc secrets.
#
# Usage:
#   sh rotate-secrets.sh              # interactive — choose which group to rotate
#   sh rotate-secrets.sh cloudflare   # rotate Cloudflare token only
#   sh rotate-secrets.sh supabase     # rotate Supabase S3 + access token
#   sh rotate-secrets.sh api          # rotate API runtime secrets (BGG, service role key)
#   sh rotate-secrets.sh all          # rotate everything
#
# Secrets and where they live:
#
#   GROUP       SECRET                         LOCAL .env   GITHUB ACTIONS   CLOUD RUN
#   ─────────── ─────────────────────────────  ──────────   ──────────────   ─────────
#   cloudflare  CLOUDFLARE_API_TOKEN           —            ✓                —
#               TF_VAR_CLOUDFLARE_ZONE_ID      —            ✓                —
#   supabase    TF_BACKEND_ACCESS_KEY          —            ✓                —
#               TF_BACKEND_SECRET_KEY          —            ✓                —
#               TF_VAR_SUPABASE_ACCESS_TOKEN   —            ✓                —
#   api         SUPABASE_SERVICE_ROLE_KEY      ✓ (.env)     —                ✓ (prod)
#               BGG_TOKEN                      ✓ (.env)     —                ✓ (prod)
#               BGG_COOKIE                     ✓ (.env)     —                ✓ (prod)
#
# After rotating api secrets, update services/api/.env manually (never automated).
# Cloud Run env vars are updated by this script if CLOUD_RUN_SERVICE is set.
#
# How to rotate:
#   - Cloudflare token: dash.cloudflare.com → Profile → API Tokens → revoke old, create new
#   - Supabase S3 key: Supabase dashboard → Storage → S3 Connection → rotate key
#   - Supabase access token: app.supabase.com → Account → Access Tokens → revoke, create
#   - Supabase service role key: dashboard → Settings → API → copy (Supabase auto-rotates on request)
#   - BGG token/cookie: copy from browser DevTools after logging into boardgamegeek.com

set -eu

REPO="LuisMedinaG/mbgc"
CLOUD_RUN_SERVICE="${CLOUD_RUN_SERVICE:-mbgc-api}"
CLOUD_RUN_REGION="${CLOUD_RUN_REGION:-us-central1}"
GCP_PROJECT="${GCP_PROJECT:-myboardgamecollection-494214}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROD_ENV="${SCRIPT_DIR}/../environments/prod"

die()               { printf 'error: %s\n' "$1" >&2; exit 1; }
prompt_secret()     { printf '%s: ' "$1"; stty -echo 2>/dev/null || true; read -r _v; stty echo 2>/dev/null || true; printf '\n'; printf '%s' "$_v"; }
prompt_or_env()     { _val="${2:-}"; if [ -z "$_val" ]; then _val="$(prompt_secret "$1")"; fi; printf '%s' "$_val"; }

set_github_secret() {
  printf '%s' "$2" | gh secret set "$1" --repo "$REPO"
  printf '  ✓ GitHub %-40s updated\n' "$1"
}

set_cloudrun_env() {
  # Build KEY=VALUE pairs for gcloud
  _pairs=""
  while [ "$#" -ge 2 ]; do
    _pairs="${_pairs}${1}=${2},"
    shift 2
  done
  _pairs="${_pairs%,}"
  gcloud run services update "$CLOUD_RUN_SERVICE" \
    --region "$CLOUD_RUN_REGION" \
    --project "$GCP_PROJECT" \
    --set-env-vars "$_pairs" \
    --quiet
  printf '  ✓ Cloud Run %-38s updated\n' "${CLOUD_RUN_SERVICE}"
}

update_tfvars() {
  _key="$1"; _val="$2"; _file="${PROD_ENV}/terraform.tfvars"
  if [ ! -f "$_file" ]; then
    printf '  ⚠ %s not found — skipping tfvars update (run bootstrap.sh first)\n' "$_file"
    return
  fi
  if grep -q "^${_key}" "$_file"; then
    sed -i.bak "s|^${_key}.*|${_key} = \"${_val}\"|" "$_file" && rm -f "${_file}.bak"
  else
    printf '%s = "%s"\n' "$_key" "$_val" >> "$_file"
  fi
  printf '  ✓ tfvars  %-40s updated\n' "$_key"
}

# ── Rotation groups ────────────────────────────────────────────────────────────

rotate_cloudflare() {
  printf '\n── Cloudflare secrets ──\n'
  printf 'Get a new token at: dash.cloudflare.com → Profile → API Tokens\n'
  printf 'Required scopes: Zone:Edit, DNS:Edit, Cloudflare Pages:Edit\n\n'

  CF_TOKEN="$(prompt_or_env 'Cloudflare API token' "${CLOUDFLARE_API_TOKEN:-}")"
  CF_ZONE="$(prompt_or_env  'Cloudflare zone ID (lumedina.dev)' "${CLOUDFLARE_ZONE_ID:-}")"

  set_github_secret CLOUDFLARE_API_TOKEN      "$CF_TOKEN"
  set_github_secret TF_VAR_CLOUDFLARE_ZONE_ID "$CF_ZONE"
  update_tfvars cloudflare_api_token          "$CF_TOKEN"
  update_tfvars cloudflare_zone_id            "$CF_ZONE"
}

rotate_supabase() {
  printf '\n── Supabase infra secrets ──\n'
  printf 'S3 key: Supabase dashboard → Storage → S3 Connection → rotate\n'
  printf 'Access token: app.supabase.com → Account → Access Tokens\n\n'

  S3_KEY="$(prompt_or_env    'Supabase S3 access key ID' "${S3_ACCESS_KEY_ID:-}")"
  S3_SECRET="$(prompt_or_env 'Supabase S3 secret key'    "${S3_SECRET_ACCESS_KEY:-}")"
  SB_TOKEN="$(prompt_or_env  'Supabase personal access token' "${SUPABASE_ACCESS_TOKEN:-}")"

  set_github_secret TF_BACKEND_ACCESS_KEY          "$S3_KEY"
  set_github_secret TF_BACKEND_SECRET_KEY          "$S3_SECRET"
  set_github_secret TF_VAR_SUPABASE_ACCESS_TOKEN   "$SB_TOKEN"
  update_tfvars supabase_access_token              "$SB_TOKEN"

  printf '\n  ℹ After rotating S3 keys, also update environments/prod/backend.hcl with\n'
  printf '    the new access key, then run: terraform init -reconfigure\n'
}

rotate_api() {
  printf '\n── API runtime secrets ──\n'
  printf 'Service role key: Supabase dashboard → Settings → API\n'
  printf 'BGG token/cookie: copy from browser DevTools on boardgamegeek.com\n\n'

  SVC_KEY="$(prompt_or_env 'Supabase service role key' "${SUPABASE_SERVICE_ROLE_KEY:-}")"
  BGG_TOKEN="$(prompt_or_env 'BGG token (leave blank to skip)' "${BGG_TOKEN:-}")"
  BGG_COOKIE="$(prompt_or_env 'BGG cookie (leave blank to skip)' "${BGG_COOKIE:-}")"

  printf '\n  Updating Cloud Run env vars...\n'
  if [ -n "$BGG_TOKEN" ] && [ -n "$BGG_COOKIE" ]; then
    set_cloudrun_env SUPABASE_SERVICE_ROLE_KEY "$SVC_KEY" BGG_TOKEN "$BGG_TOKEN" BGG_COOKIE "$BGG_COOKIE"
  elif [ -n "$BGG_TOKEN" ]; then
    set_cloudrun_env SUPABASE_SERVICE_ROLE_KEY "$SVC_KEY" BGG_TOKEN "$BGG_TOKEN"
  else
    set_cloudrun_env SUPABASE_SERVICE_ROLE_KEY "$SVC_KEY"
  fi

  printf '\n  ⚠ Update services/api/.env manually with the new values.\n'
  printf '    (Local .env files are never written by this script.)\n'
}

# ── Main ──────────────────────────────────────────────────────────────────────

command -v gh >/dev/null 2>&1     || die "'gh' is required (brew install gh)"
command -v gcloud >/dev/null 2>&1 || die "'gcloud' is required for Cloud Run updates"
gh auth status >/dev/null 2>&1    || die "Not authenticated with gh. Run: gh auth login"

GROUP="${1:-}"

if [ -z "$GROUP" ]; then
  printf '\nWhich secrets do you want to rotate?\n'
  printf '  1) cloudflare   — API token, zone ID\n'
  printf '  2) supabase     — S3 keys, personal access token\n'
  printf '  3) api          — service role key, BGG token/cookie\n'
  printf '  4) all          — everything above\n'
  printf '\nChoice [1-4]: '
  read -r choice
  case "$choice" in
    1) GROUP=cloudflare ;;
    2) GROUP=supabase   ;;
    3) GROUP=api        ;;
    4) GROUP=all        ;;
    *) die "invalid choice" ;;
  esac
fi

case "$GROUP" in
  cloudflare) rotate_cloudflare ;;
  supabase)   rotate_supabase   ;;
  api)        rotate_api        ;;
  all)
    rotate_cloudflare
    rotate_supabase
    rotate_api
    ;;
  *) die "unknown group: $GROUP. Use: cloudflare | supabase | api | all" ;;
esac

printf '\n✓ Secret rotation complete.\n'
printf '  Review the summary above and verify in GitHub → Settings → Secrets.\n'
