#!/bin/sh
set -eu

WIP='projects/1017761519272/locations/global/workloadIdentityPools/github-actions/providers/github'
DEPLOY_SA='github-deploy@myboardgamecollection-494214.iam.gserviceaccount.com'
PROJECT='myboardgamecollection-494214'

set_secrets() {
  local repo="$1" runtime_sa="$2"
  echo "Setting secrets for LuisMedinaG/$repo..."
  gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --repo "LuisMedinaG/$repo" --body "$WIP"
  gh secret set GCP_SERVICE_ACCOUNT            --repo "LuisMedinaG/$repo" --body "$DEPLOY_SA"
  gh secret set GCP_PROJECT_ID                 --repo "LuisMedinaG/$repo" --body "$PROJECT"
  gh secret set GCP_RUNTIME_SERVICE_ACCOUNT    --repo "LuisMedinaG/$repo" --body "$runtime_sa"
}

set_secrets mbgc-gateway          run-mbgc-gateway@myboardgamecollection-494214.iam.gserviceaccount.com
set_secrets mbgc-auth-service     run-mbgc-auth-service@myboardgamecollection-494214.iam.gserviceaccount.com
set_secrets mbgc-game-service     run-mbgc-game-service@myboardgamecollection-494214.iam.gserviceaccount.com
set_secrets mbgc-importer-service run-mbgc-importer-service@myboardgamecollection-494214.iam.gserviceaccount.com
set_secrets myboardgamecollection run-myboardgamecollection@myboardgamecollection-494214.iam.gserviceaccount.com

echo "Done."
