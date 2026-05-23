#!/bin/sh
# Set GitHub secrets for the mbgc monorepo.
# Run this after `terraform apply` has populated the outputs.
set -eu

REPO="LuisMedinaG/mbgc"

echo "Setting secrets for $REPO..."

# GCP Workload Identity Federation
WIP=$(terraform -chdir=infra/environments/prod output -raw workload_identity_provider 2>/dev/null || echo "")
if [ -n "$WIP" ]; then
  echo "$WIP" | gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --repo "$REPO"
  echo "  ✓ GCP_WORKLOAD_IDENTITY_PROVIDER"
fi

# Deploy service account
DEPLOY_SA=$(terraform -chdir=infra/environments/prod output -raw deploy_service_account 2>/dev/null || echo "")
if [ -n "$DEPLOY_SA" ]; then
  echo "$DEPLOY_SA" | gh secret set GCP_SERVICE_ACCOUNT --repo "$REPO"
  echo "  ✓ GCP_SERVICE_ACCOUNT"
fi

# Project ID
echo "myboardgamecollection-494214" | gh secret set GCP_PROJECT_ID --repo "$REPO"
echo "  ✓ GCP_PROJECT_ID"

# Runtime service accounts (all services)
RUNTIME_SAS=$(terraform -chdir=infra/environments/prod output -json runtime_service_accounts 2>/dev/null || echo "{}")
if [ "$RUNTIME_SAS" != "{}" ]; then
  # Set a combined secret with all runtime SAs
  echo "$RUNTIME_SAS" | gh secret set GCP_RUNTIME_SERVICE_ACCOUNTS --repo "$REPO"
  echo "  ✓ GCP_RUNTIME_SERVICE_ACCOUNTS"
fi

# Cloudflare (for web deploy)
CF_TOKEN=$(grep cloudflare_api_token infra/environments/prod/terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "")
if [ -n "$CF_TOKEN" ]; then
  echo "$CF_TOKEN" | gh secret set CLOUDFLARE_API_TOKEN --repo "$REPO"
  echo "  ✓ CLOUDFLARE_API_TOKEN"
fi

CF_ACCOUNT=$(grep cloudflare_account_id infra/environments/prod/terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "")
if [ -n "$CF_ACCOUNT" ]; then
  echo "$CF_ACCOUNT" | gh secret set CLOUDFLARE_ACCOUNT_ID --repo "$REPO"
  echo "  ✓ CLOUDFLARE_ACCOUNT_ID"
fi

echo ""
echo "Done. Verify with: gh secret list --repo $REPO"
