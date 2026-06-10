#!/bin/sh
# infra/scripts/bootstrap.sh — GCP provider
#
# One-time infra provisioning: creates the Terraform GCP service account,
# writes local credential files, syncs secrets to GitHub, and runs terraform init.
# Idempotent — safe to re-run. Re-runs are silent when infra/.env is complete.
#
# CI authenticates to GCP via Workload Identity Federation (no long-lived key).
# Local runs use Application Default Credentials (gcloud auth application-default login).

set -eu

# ── Constants ──────────────────────────────────────────────────────────────────

REPO="LuisMedinaG/mbgc"
GCP_SA_NAME="terraform"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_ENV="${SCRIPT_DIR}/../.env"
ENV_DIR="${SCRIPT_DIR}/../environments/prod"
DEV_ENV_DIR="${SCRIPT_DIR}/../environments/dev"

# ── Shared helpers ─────────────────────────────────────────────────────────────

# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

# ── save_env ───────────────────────────────────────────────────────────────────
# Persists all collected vars to infra/.env on every exit (via trap below).
# Listed here because the variable set is specific to this provider/project.

save_env() {
  cat > "$INFRA_ENV" <<ENVEOF
# mbgc infra config — written by bootstrap.sh
# gitignored. Re-run bootstrap.sh to update.

DOMAIN="${DOMAIN:-}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
SUPABASE_PROJECT_REF="${SUPABASE_PROJECT_REF:-}"
SUPABASE_ACCESS_TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
S3_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID:-}"
S3_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY:-}"
CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"
API_DATABASE_URL="${API_DATABASE_URL:-}"
API_SUPABASE_URL="${API_SUPABASE_URL:-}"
API_SUPABASE_SERVICE_ROLE_KEY="${API_SUPABASE_SERVICE_ROLE_KEY:-}"
API_ALLOWED_ORIGIN="${API_ALLOWED_ORIGIN:-}"
DEV_API_DATABASE_URL="${DEV_API_DATABASE_URL:-}"
DEV_API_SUPABASE_URL="${DEV_API_SUPABASE_URL:-}"
DEV_API_SUPABASE_SERVICE_ROLE_KEY="${DEV_API_SUPABASE_SERVICE_ROLE_KEY:-}"
DEV_API_ALLOWED_ORIGIN="${DEV_API_ALLOWED_ORIGIN:-}"
DEV_API_SEED_ADMIN_EMAIL="${DEV_API_SEED_ADMIN_EMAIL:-}"
DEV_API_SEED_ADMIN_PASSWORD="${DEV_API_SEED_ADMIN_PASSWORD:-}"
DEV_API_SEED_ADMIN_USERNAME="${DEV_API_SEED_ADMIN_USERNAME:-}"
ENVEOF
  chmod 600 "$INFRA_ENV"
}

# ── Config ─────────────────────────────────────────────────────────────────────

[ -f "$INFRA_ENV" ] || die "infra/.env not found — run: make setup-infra"
# shellcheck disable=SC1090
. "$INFRA_ENV"

_missing=""
for _var in DOMAIN GCP_PROJECT_ID CF_ACCOUNT_ID SUPABASE_PROJECT_REF; do
  eval "_val=\${${_var}:-}"
  [ -n "$_val" ] || _missing="${_missing}  ${_var}\n"
done
if [ -n "$_missing" ]; then
  printf 'error: required vars missing from infra/.env:\n%b' "$_missing" >&2
  exit 1
fi

GCP_SA_EMAIL="${GCP_SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
API_DOMAIN="api.${DOMAIN}"
SUPABASE_S3_ENDPOINT="https://${SUPABASE_PROJECT_REF}.storage.supabase.co/storage/v1/s3"

trap save_env EXIT

# ── Prerequisites ──────────────────────────────────────────────────────────────

printf '=== mbgc infra bootstrap ===\n\n'
printf '── prerequisites ──\n'

check_cmd terraform
check_cmd gh
check_cmd gcloud
check_cmd jq

gh auth status >/dev/null 2>&1 \
  || die "not authenticated with gh — run: gh auth login"
gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null \
  | grep -q . \
  || die "not authenticated with gcloud — run: gcloud auth login"

printf '  ✓ all tools present and authenticated\n'
printf '  ✓ loaded config from %s\n' "$INFRA_ENV"

# ── GCP service account ────────────────────────────────────────────────────────

printf '\n── gcp service account ──\n'

for _api in \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com; do
  gcloud services enable "$_api" --project "$GCP_PROJECT_ID" >/dev/null 2>&1 || true
done
printf '  ✓ APIs enabled\n'

if ! gcloud iam service-accounts describe "$GCP_SA_EMAIL" \
     --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$GCP_SA_NAME" \
    --project "$GCP_PROJECT_ID" \
    --display-name "Terraform" >/dev/null
fi
printf '  ✓ service account: %s\n' "$GCP_SA_EMAIL"

for _role in \
  roles/run.admin \
  roles/iam.serviceAccountUser \
  roles/iam.serviceAccountAdmin \
  roles/iam.workloadIdentityPoolAdmin \
  roles/artifactregistry.admin \
  roles/resourcemanager.projectIamAdmin \
  roles/serviceusage.serviceUsageAdmin \
  roles/logging.configWriter \
  roles/monitoring.admin; do
  gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
    --member "serviceAccount:${GCP_SA_EMAIL}" \
    --role "$_role" \
    --condition=None >/dev/null 2>&1
done
printf '  ✓ IAM roles granted\n'

printf '\n── application default credentials ──\n'
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  gcloud auth application-default login
else
  printf '  ✓ ADC configured\n'
fi

# ── Credentials ────────────────────────────────────────────────────────────────

printf '\n── credentials ──\n'

prompt_secret SUPABASE_ACCESS_TOKEN \
  "Supabase personal access token (app.supabase.com → Account → Access Tokens)" \
  "${SUPABASE_ACCESS_TOKEN:-}"

prompt_secret S3_ACCESS_KEY_ID \
  "Supabase S3 access key ID (Storage → S3 Connection)" \
  "${S3_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
prompt_secret S3_SECRET_ACCESS_KEY \
  "Supabase S3 secret access key" \
  "${S3_SECRET_ACCESS_KEY:-}"

prompt_secret CLOUDFLARE_API_TOKEN \
  "Cloudflare API token (Zone:Edit + Pages:Edit + DNS:Edit)" \
  "${CLOUDFLARE_API_TOKEN:-}"
prompt_value CF_ACCOUNT_ID \
  "Cloudflare account ID" \
  "${CF_ACCOUNT_ID:-}" \
  ""
prompt_value CLOUDFLARE_ZONE_ID \
  "Cloudflare zone ID for ${DOMAIN}" \
  "${CLOUDFLARE_ZONE_ID:-}" \
  ""

printf '\n── cloudflare token validation ──\n'
_cf_response="$(curl -s -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  https://api.cloudflare.com/client/v4/user/tokens/verify || printf '{}')"
_cf_status="$(printf '%s' "$_cf_response" | jq -r '.success // false')"
if [ "$_cf_status" = "true" ]; then
  _cf_token_id="$(printf '%s' "$_cf_response" | jq -r '.result.id // "unknown"')"
  printf '  ✓ token valid (id: %s)\n' "${_cf_token_id:0:16}..."
else
  _cf_error="$(printf '%s' "$_cf_response" | jq -r '.errors[0].message // "unknown error"')"
  die "invalid cloudflare token — $_cf_error (see: dash.cloudflare.com/profile/api-tokens)"
fi

printf '\n  prod API (Supabase → Settings → Database / API):\n'
prompt_secret API_DATABASE_URL \
  "Prod DATABASE_URL (Settings → Database → URI, port 5432)" \
  "${API_DATABASE_URL:-}"
prompt_value API_SUPABASE_URL \
  "Prod SUPABASE_URL" \
  "${API_SUPABASE_URL:-}" \
  "https://${SUPABASE_PROJECT_REF}.supabase.co"
prompt_secret API_SUPABASE_SERVICE_ROLE_KEY \
  "Prod service_role key (Settings → API → Legacy API keys)" \
  "${API_SUPABASE_SERVICE_ROLE_KEY:-}"
prompt_value API_ALLOWED_ORIGIN \
  "Prod ALLOWED_ORIGIN" \
  "${API_ALLOWED_ORIGIN:-}" \
  "https://${DOMAIN}"

printf '\n  dev API:\n'
prompt_secret DEV_API_DATABASE_URL \
  "Dev DATABASE_URL (Settings → Database → URI, port 5432)" \
  "${DEV_API_DATABASE_URL:-}"
prompt_value DEV_API_SUPABASE_URL \
  "Dev SUPABASE_URL" \
  "${DEV_API_SUPABASE_URL:-}" \
  ""
prompt_secret DEV_API_SUPABASE_SERVICE_ROLE_KEY \
  "Dev service_role key (Settings → API → Legacy API keys)" \
  "${DEV_API_SUPABASE_SERVICE_ROLE_KEY:-}"
prompt_value DEV_API_ALLOWED_ORIGIN \
  "Dev ALLOWED_ORIGIN (or * to allow all)" \
  "${DEV_API_ALLOWED_ORIGIN:-}" \
  "*"
prompt_optional DEV_API_SEED_ADMIN_EMAIL \
  "Dev admin email (optional — leave blank to skip seeding)" \
  "${DEV_API_SEED_ADMIN_EMAIL:-}"
prompt_secret_optional DEV_API_SEED_ADMIN_PASSWORD \
  "Dev admin password (optional)" \
  "${DEV_API_SEED_ADMIN_PASSWORD:-}"
prompt_optional DEV_API_SEED_ADMIN_USERNAME \
  "Dev admin username (optional display name)" \
  "${DEV_API_SEED_ADMIN_USERNAME:-}"

# ── Local credential files ─────────────────────────────────────────────────────

printf '\n── local credential files ──\n'

cat > "${ENV_DIR}/backend.hcl" <<EOF
bucket    = "mbgc-tfstate"
endpoints = { s3 = "${SUPABASE_S3_ENDPOINT}" }
EOF
printf '  ✓ %s\n' "${ENV_DIR}/backend.hcl"

cat > "${ENV_DIR}/terraform.tfvars" <<EOF
cloudflare_api_token  = "${CLOUDFLARE_API_TOKEN}"
cloudflare_account_id = "${CF_ACCOUNT_ID}"
cloudflare_zone_id    = "${CLOUDFLARE_ZONE_ID}"
supabase_access_token = "${SUPABASE_ACCESS_TOKEN}"
EOF
printf '  ✓ %s\n' "${ENV_DIR}/terraform.tfvars"

# ── GitHub secrets ─────────────────────────────────────────────────────────────

sync_secrets "github secrets — cloudflare (deploy.yml)" \
  CLOUDFLARE_API_TOKEN  "$CLOUDFLARE_API_TOKEN" \
  CLOUDFLARE_ACCOUNT_ID "$CF_ACCOUNT_ID"

sync_secrets "github secrets — terraform backend (infra.yml)" \
  TF_BACKEND_ACCESS_KEY "$S3_ACCESS_KEY_ID" \
  TF_BACKEND_SECRET_KEY "$S3_SECRET_ACCESS_KEY"

sync_secrets "github secrets — terraform provider vars (infra.yml)" \
  TF_VAR_CLOUDFLARE_ZONE_ID    "$CLOUDFLARE_ZONE_ID" \
  TF_VAR_SUPABASE_ACCESS_TOKEN "$SUPABASE_ACCESS_TOKEN"

sync_secrets "github secrets — prod API (deploy.yml)" \
  API_DATABASE_URL              "$API_DATABASE_URL" \
  API_SUPABASE_URL              "$API_SUPABASE_URL" \
  API_SUPABASE_SERVICE_ROLE_KEY "$API_SUPABASE_SERVICE_ROLE_KEY" \
  API_ALLOWED_ORIGIN            "$API_ALLOWED_ORIGIN"

sync_secrets "github secrets — dev API (deploy.yml)" \
  DEV_API_DATABASE_URL              "$DEV_API_DATABASE_URL" \
  DEV_API_SUPABASE_URL              "$DEV_API_SUPABASE_URL" \
  DEV_API_SUPABASE_SERVICE_ROLE_KEY "$DEV_API_SUPABASE_SERVICE_ROLE_KEY" \
  DEV_API_ALLOWED_ORIGIN            "$DEV_API_ALLOWED_ORIGIN"
sync_secrets_optional "github secrets — dev API seed admin (optional)" \
  DEV_API_SEED_ADMIN_EMAIL          "$DEV_API_SEED_ADMIN_EMAIL" \
  DEV_API_SEED_ADMIN_PASSWORD       "$DEV_API_SEED_ADMIN_PASSWORD" \
  DEV_API_SEED_ADMIN_USERNAME       "$DEV_API_SEED_ADMIN_USERNAME"

# ── Terraform init ─────────────────────────────────────────────────────────────

printf '\n── terraform init ──\n'

export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"

cd "$ENV_DIR"
terraform init -backend-config=backend.hcl -upgrade -input=false

# Post-apply: sync WIF and deploy SA secrets once terraform state has outputs.
# Re-run bootstrap after `terraform apply` to push these.
if terraform output -raw workload_identity_provider >/dev/null 2>&1; then
  _runtime_sas="$(terraform output -json runtime_service_accounts)"
  sync_secrets "github secrets — gcp deploy (post-apply)" \
    GCP_WORKLOAD_IDENTITY_PROVIDER "$(terraform output -raw workload_identity_provider)" \
    GCP_SERVICE_ACCOUNT            "$(terraform output -raw deploy_service_account)" \
    GCP_TERRAFORM_SERVICE_ACCOUNT  "$(terraform output -raw terraform_service_account)" \
    GCP_PROJECT_ID                 "$GCP_PROJECT_ID" \
    GCP_RUNTIME_SA_API             "$(printf '%s' "$_runtime_sas" | jq -r '."mbgc-api"')"
fi

# Dev environment runtime SA — available after `terraform apply` in environments/dev/.
if [ -f "${DEV_ENV_DIR}/backend.hcl" ]; then
  cd "$DEV_ENV_DIR"
  if terraform init -backend-config=backend.hcl -input=false >/dev/null 2>&1 \
      && terraform output -raw runtime_service_account >/dev/null 2>&1; then
    sync_secrets "github secrets — dev runtime SA" \
      GCP_RUNTIME_SA_API_DEV "$(terraform output -raw runtime_service_account)"
  fi
  cd "$ENV_DIR"
fi

# ── Next steps ─────────────────────────────────────────────────────────────────

printf '\n=== bootstrap complete ===\n\n'

_step=1

if ! gcloud run domain-mappings describe "$API_DOMAIN" \
     --region us-central1 --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
  printf '%d. Verify %s in Google Search Console and grant the Terraform SA owner access:\n' \
    "$_step" "$DOMAIN"
  printf '     SA:  %s\n' "$GCP_SA_EMAIL"
  printf '     URL: https://search.google.com/search-console/welcome\n'
  printf '     → Add property → Domain → "%s"\n' "$DOMAIN"
  printf '     → Settings → Users and permissions → Add user → %s (Owner)\n\n' "$GCP_SA_EMAIL"
  _step=$((_step + 1))
else
  printf '  ✓ %s domain mapping exists\n\n' "$API_DOMAIN"
fi

printf '%d. cd infra/environments/prod && terraform plan && terraform apply\n' "$_step"
_step=$((_step + 1))
printf '%d. Re-run this script after apply to push GCP deploy secrets to %s.\n' "$_step" "$REPO"
