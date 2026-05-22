#!/bin/sh
# Bootstrap: provisions the terraform GCP SA, writes local credential files,
# syncs GitHub secrets, and runs `terraform init`. Idempotent — safe to re-run.
#
# CI authenticates to GCP via Workload Identity Federation (no long-lived key).
# Local authentication uses Application Default Credentials.
set -eu

REPO="LuisMedinaG/mbgc-infra"
GCP_PROJECT_ID="myboardgamecollection-494214"
GCP_SA_NAME="terraform"
GCP_SA_EMAIL="${GCP_SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
CF_ACCOUNT_ID="b54fbd0d522b22fc747619b57608bb72"
SUPABASE_PROJECT_REF="mlltpfszhtxhphoaeydh"
SUPABASE_S3_ENDPOINT="https://${SUPABASE_PROJECT_REF}.storage.supabase.co/storage/v1/s3"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_DIR="${SCRIPT_DIR}/../environments/prod"

###############################################################################
# Helpers
###############################################################################

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

check_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed"
}

use_or_prompt() {
  _var="$1"; _desc="$2"; _env_val="${3:-}"; _default="${4:-}"
  if [ -n "$_env_val" ]; then
    eval "${_var}=\"\${_env_val}\""
    printf '  ✓ %s (from environment)\n' "$_desc"
    return
  fi
  if [ -n "$_default" ]; then
    printf '%s [%s]: ' "$_desc" "$_default"
  else
    printf '%s: ' "$_desc"
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

use_or_prompt_secret() {
  _var="$1"; _desc="$2"; _env_val="${3:-}"
  if [ -n "$_env_val" ]; then
    eval "${_var}=\"\${_env_val}\""
    printf '  ✓ %s (from environment)\n' "$_desc"
    return
  fi
  printf '%s: ' "$_desc"
  stty -echo 2>/dev/null || true
  read -r _input
  stty echo 2>/dev/null || true
  printf '\n'
  [ -n "$_input" ] || die "$_desc is required"
  eval "${_var}=\"\${_input}\""
}

set_secret() {
  printf '%s' "$2" | gh secret set "$1" --repo "$REPO"
  printf '  ✓ %s\n' "$1"
}

###############################################################################
# Prerequisites
###############################################################################

printf '\n=== mbgc-infra bootstrap ===\n\n'

check_cmd terraform
check_cmd gh
check_cmd gcloud

if ! gh auth status >/dev/null 2>&1; then
  die "Not authenticated with gh. Run: gh auth login"
fi

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
  die "Not authenticated with gcloud. Run: gcloud auth login"
fi

###############################################################################
# GCP — terraform service account (no key; CI auths via WIF)
###############################################################################

printf 'Setting up GCP service account...\n\n'

# Enable required APIs.
for api in run.googleapis.com artifactregistry.googleapis.com iamcredentials.googleapis.com cloudresourcemanager.googleapis.com; do
  gcloud services enable "$api" --project "$GCP_PROJECT_ID" >/dev/null 2>&1 || true
done

if ! gcloud iam service-accounts describe "$GCP_SA_EMAIL" --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$GCP_SA_NAME" \
    --project "$GCP_PROJECT_ID" \
    --display-name "Terraform" >/dev/null
  printf '  ✓ service account created: %s\n' "$GCP_SA_EMAIL"
else
  printf '  ✓ service account exists: %s\n' "$GCP_SA_EMAIL"
fi

for role in \
  roles/run.admin \
  roles/iam.serviceAccountUser \
  roles/iam.serviceAccountAdmin \
  roles/iam.workloadIdentityPoolAdmin \
  roles/artifactregistry.admin \
  roles/resourcemanager.projectIamAdmin \
  roles/serviceusage.serviceUsageAdmin; do
  gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
    --member "serviceAccount:${GCP_SA_EMAIL}" \
    --role "$role" \
    --condition=None >/dev/null 2>&1
done
printf '  ✓ IAM roles granted\n\n'

printf 'Ensuring local Application Default Credentials...\n'
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  gcloud auth application-default login
else
  printf '  ✓ ADC already configured\n'
fi
printf '\n'

###############################################################################
# Collect remaining credentials
###############################################################################

printf 'Collecting credentials...\n\n'

use_or_prompt_secret SUPABASE_ACCESS_TOKEN \
  "Supabase personal access token (app.supabase.com → Account → Access Tokens)" \
  "${SUPABASE_ACCESS_TOKEN:-}"

printf '\n'
use_or_prompt_secret S3_ACCESS_KEY_ID \
  "Supabase S3 access key ID (dashboard → Storage → S3 Connection)" \
  "${S3_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
use_or_prompt_secret S3_SECRET_ACCESS_KEY \
  "Supabase S3 secret access key" \
  "${S3_SECRET_ACCESS_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"

printf '\n'
use_or_prompt_secret CLOUDFLARE_API_TOKEN \
  "Cloudflare API token (Zone:Edit + Pages:Edit + DNS:Edit)" \
  "${CLOUDFLARE_API_TOKEN:-}"
use_or_prompt CF_ACCOUNT_ID \
  "Cloudflare account ID" \
  "" \
  "$CF_ACCOUNT_ID"
use_or_prompt CLOUDFLARE_ZONE_ID \
  "Cloudflare zone ID for lumedina.dev" \
  "${CLOUDFLARE_ZONE_ID:-}" \
  ""

###############################################################################
# Write local credential files
###############################################################################

printf '\nWriting local credential files...\n'

BACKEND_HCL="${ENV_DIR}/backend.hcl"
TFVARS="${ENV_DIR}/terraform.tfvars"

cat > "$BACKEND_HCL" <<EOF
bucket    = "mbgc-tfstate"
endpoints = { s3 = "${SUPABASE_S3_ENDPOINT}" }
EOF
printf '  ✓ %s\n' "$BACKEND_HCL"

cat > "$TFVARS" <<EOF
cloudflare_api_token  = "${CLOUDFLARE_API_TOKEN}"
cloudflare_account_id = "${CF_ACCOUNT_ID}"
cloudflare_zone_id    = "${CLOUDFLARE_ZONE_ID}"
supabase_access_token = "${SUPABASE_ACCESS_TOKEN}"
EOF
printf '  ✓ %s\n' "$TFVARS"

###############################################################################
# Sync GitHub secrets
###############################################################################

printf '\nSyncing GitHub secrets on %s...\n' "$REPO"

set_secret SUPABASE_ACCESS_TOKEN  "$SUPABASE_ACCESS_TOKEN"
set_secret S3_ACCESS_KEY_ID       "$S3_ACCESS_KEY_ID"
set_secret S3_SECRET_ACCESS_KEY   "$S3_SECRET_ACCESS_KEY"
set_secret CLOUDFLARE_API_TOKEN   "$CLOUDFLARE_API_TOKEN"
set_secret CLOUDFLARE_ACCOUNT_ID  "$CF_ACCOUNT_ID"
set_secret CLOUDFLARE_ZONE_ID     "$CLOUDFLARE_ZONE_ID"

###############################################################################
# Terraform init
###############################################################################

printf '\nRunning terraform init...\n'
cd "$ENV_DIR"

export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"

terraform init -backend-config=backend.hcl -upgrade -input=false

###############################################################################
# Post-apply: sync WIF secrets if terraform state already has them
###############################################################################

if terraform output -raw workload_identity_provider >/dev/null 2>&1; then
  printf '\nSyncing WIF secrets (state has outputs)...\n'
  WIF_PROVIDER="$(terraform output -raw workload_identity_provider)"
  TF_SA="$(terraform output -raw terraform_service_account)"
  set_secret GCP_WORKLOAD_IDENTITY_PROVIDER "$WIF_PROVIDER"
  set_secret GCP_TERRAFORM_SERVICE_ACCOUNT  "$TF_SA"
fi

printf '\n=== Bootstrap complete ===\n\n'
printf 'Next steps:\n'
printf '  1. Verify lumedina.dev in Google Search Console and add %s as an owner\n' "$GCP_SA_EMAIL"
printf '     (required before google_cloud_run_domain_mapping.api can apply).\n'
printf '\n  2. terraform plan && terraform apply\n'
printf '\n  3. Re-run this script to push GCP_WORKLOAD_IDENTITY_PROVIDER and\n'
printf '     GCP_TERRAFORM_SERVICE_ACCOUNT to GitHub (needed for CI).\n'
printf '\n  4. sh scripts/set-deploy-secrets.sh   # push WIF outputs to service repos\n'
