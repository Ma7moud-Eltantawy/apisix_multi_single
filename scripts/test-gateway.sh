#!/usr/bin/env bash
# ============================================================
#  APISIX Local Stack - Gateway Test Script (Linux/macOS)
# ============================================================

ADMIN_KEY="edd1c9f034335f136f87ad84b625c8f1"
BASE="http://localhost"
PASS=0; FAIL=0

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

check() {
    local desc="$1" url="$2" expected="$3"
    status=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    if [[ "$status" == "$expected" || ( "$expected" == "2xx" && "$status" =~ ^2 ) ]]; then
        echo -e "  ${GREEN}✅ PASS${NC} - $desc [HTTP $status]"
        ((PASS++))
    else
        echo -e "  ${RED}❌ FAIL${NC} - $desc [HTTP $status, expected $expected]"
        ((FAIL++))
    fi
}

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║     APISIX Local Stack - Health Tests        ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

check "Admin API (port 9180)"        "$BASE:9180/apisix/admin/routes -H X-API-KEY:$ADMIN_KEY" "200"
check "Dashboard (port 9000)"         "$BASE:9000"                      "200"
check "Prometheus (port 9090)"        "$BASE:9090/-/ready"              "200"
check "Grafana (port 3000)"           "$BASE:3000/api/health"           "200"
check "APISIX Metrics (port 9091)"    "$BASE:9091/apisix/prometheus/metrics" "200"

echo ""
echo -e "${YELLOW}[Creating test route → httpbin.org]${NC}"
curl -s -o /dev/null -X PUT "$BASE:9180/apisix/admin/routes/test-route" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"uri":"/test","name":"test-route","upstream":{"type":"roundrobin","nodes":{"httpbin.org:80":1}}}'
echo ""

echo -e "${YELLOW}[Testing gateway route: GET /test/get]${NC}"
status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE:9080/test/get")
echo -e "  Gateway returned HTTP $status"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo -e "║  Results: ${GREEN}$PASS PASSED${NC} / ${RED}$FAIL FAILED${NC}"
echo "╚══════════════════════════════════════════════╝"
echo ""
