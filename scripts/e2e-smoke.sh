#!/usr/bin/env bash
# Minimal e2e smoke test — verifies API is alive and auth gating works
set -eu

API="${API:-http://localhost:8080}"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { printf "${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "${RED}✗${NC} %s — %s\n" "$1" "$2"; FAILED=1; }

echo "=== mbgc e2e smoke ==="

# 1. Health check
echo ""
echo "--- Health ---"
[[ $(curl -sf "$API/readyz" | grep -c '"ok"') -gt 0 ]] && pass "api /readyz" || fail "api /readyz" "$(curl -s "$API/readyz")"

# 2. Auth gating — unauthenticated requests blocked
echo ""
echo "--- Auth gating ---"
for path in "/api/v1/games" "/api/v1/profile" "/api/v1/import/sync"; do
  code=$(curl -sk -o /dev/null -w "%{http_code}" "$API$path")
  [[ "$code" = "401" ]] && pass "401 on $path" || fail "401 on $path" "got $code"
done

# 3. JWT validation — fake token blocked
echo ""
echo "--- JWT validation ---"
code=$(curl -sk -o /dev/null -w "%{http_code}" -H "Authorization: Bearer fake-token" "$API/api/v1/games")
[[ "$code" = "401" ]] && pass "rejects fake JWT" || fail "rejects fake JWT" "got $code"

# 4. CORS headers present
echo ""
echo "--- CORS ---"
origin=$(curl -sk -I -H "Origin: http://localhost:5173" "$API/readyz" 2>&1 | grep -i "access-control-allow-origin" || echo "")
[[ -n "$origin" ]] && pass "CORS headers present" || fail "CORS headers present" "missing"

echo ""
echo "=== $( [[ -z "${FAILED:-}" ]] && echo "${GREEN}ALL PASSED${NC}" || echo "${RED}SOME FAILED${NC}" ) ==="
exit ${FAILED:-0}
