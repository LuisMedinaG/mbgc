#!/bin/sh
# [DEPRECATED] This script was for the old multi-repo setup.
# With the monorepo consolidation, deploy secrets are now managed
# at the single repo level. See infra/scripts/bootstrap.sh for
# the new workflow.
#
# Old usage (per-service repos):
#   set_secrets mbgc-gateway run-mbgc-gateway@...
#   set_secrets mbgc-auth-service run-mbgc-auth-service@...
#   ...
#
# New usage (monorepo):
#   sh infra/scripts/bootstrap.sh
#   # This sets all secrets for the single mbgc repo

set -eu

REPO="LuisMedinaG/mbgc"
WIP='projects/1017761519272/locations/global/workloadIdentityPools/github-actions/providers/github'
DEPLOY_SA='github-deploy@myboardgamecollection-494214.iam.gserviceaccount.com'
PROJECT='myboardgamecollection-494214'

echo "Setting secrets for $REPO..."
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --repo "$REPO" --body "$WIP"
gh secret set GCP_SERVICE_ACCOUNT            --repo "$REPO" --body "$DEPLOY_SA"
gh secret set GCP_PROJECT_ID                 --repo "$REPO" --body "$PROJECT"

echo "Done. Run 'sh infra/scripts/bootstrap.sh' for full setup."
