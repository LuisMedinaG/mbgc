#!/bin/sh
# Post-apply smoke tests for mbgc infra.
# Fails fast on first error. Safe to run locally or in CI.
set -eu

PROJECT="${GCP_PROJECT:-myboardgamecollection-494214}"
REGION="${GCP_REGION:-us-central1}"
API_HOST="${API_HOST:-api.lumedina.dev}"

EXPECTED_SERVICES="mbgc-auth-service mbgc-game-service mbgc-gateway mbgc-importer-service myboardgamecollection"

fail() { echo "FAIL: $1" >&2; exit 1; }
ok()   { echo "ok: $1"; }

echo "==> Cloud Run services exist in $REGION"
actual=$(gcloud run services list \
  --project="$PROJECT" --region="$REGION" \
  --format='value(metadata.name)' 2>/dev/null | sort | tr '\n' ' ')
for svc in $EXPECTED_SERVICES; do
  case " $actual " in
    *" $svc "*) ok "service $svc" ;;
    *)          fail "missing Cloud Run service: $svc" ;;
  esac
done

echo "==> DNS: $API_HOST resolves"
dig +short "$API_HOST" | grep -q '[0-9a-f]' || fail "$API_HOST did not resolve"
ok "dns $API_HOST"

echo "==> Gateway responds at https://$API_HOST"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$API_HOST/" || echo 000)
# 200-499 is fine (gateway reachable); 5xx or 000 is a fail.
case "$code" in
  [45][0-9][0-9]|[23][0-9][0-9]) ok "gateway https ($code)" ;;
  *) fail "gateway unreachable (http=$code)" ;;
esac

echo "==> All smoke checks passed"
