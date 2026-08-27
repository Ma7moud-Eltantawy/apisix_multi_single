#!/usr/bin/env bash
# ============================================================
#  APISIX Local Stack - Start Script (Linux/macOS) - Qyadati
# ============================================================

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}       Apache APISIX - Local Stack (Qyadati)                ${NC}"
echo -e "${BLUE}  etcd | gateway | dashboard | monitoring                  ${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Docker is not running! Please start Docker first.${NC}"
    exit 1
fi

echo -e "${YELLOW}[1/3] Pulling latest images...${NC}"
docker compose pull --quiet
echo ""

echo -e "${YELLOW}[2/3] Starting all services...${NC}"
docker compose up -d
echo ""

echo -e "${YELLOW}[3/3] Waiting for APISIX to be healthy...${NC}"
sleep 10

until docker compose ps apisix | grep -q "healthy"; do
    echo "  Waiting for APISIX gateway..."
    sleep 5
done

if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

DASHBOARD_USER=${DASHBOARD_USER:-admin}
DASHBOARD_PASS=${DASHBOARD_PASS:-AdminQyadati2026}
ADMIN_KEY=${ADMIN_KEY:-edd1c9f034335f136f87ad84b625c8f1}
APISIX_HTTP_PORT=${APISIX_HTTP_PORT:-9280}
APISIX_HTTPS_PORT=${APISIX_HTTPS_PORT:-9444}
APISIX_ADMIN_PORT=${APISIX_ADMIN_PORT:-9181}
CLASSIC_DASHBOARD_PORT=${CLASSIC_DASHBOARD_PORT:-9012}
ADMIN_PROXY_PORT=${ADMIN_PROXY_PORT:-9013}

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  All services are UP and HEALTHY!                          ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${GREEN}  Gateway (HTTP):      http://localhost:${APISIX_HTTP_PORT}${NC}"
echo -e "${GREEN}  Gateway (HTTPS):     https://localhost:${APISIX_HTTPS_PORT}${NC}"
echo -e "${GREEN}  Admin API:           http://localhost:${APISIX_ADMIN_PORT}${NC}"
echo -e "${GREEN}  Classic Dashboard:   http://localhost:${CLASSIC_DASHBOARD_PORT}${NC}"
echo -e "${GREEN}  Unified Admin Proxy: http://localhost:${ADMIN_PROXY_PORT}${NC}"
echo ""
echo -e "${GREEN}------------------------------------------------------------${NC}"
echo -e "${GREEN}  Dashboard Login:     ${DASHBOARD_USER} / ${DASHBOARD_PASS}${NC}"
echo -e "${GREEN}  Admin Key:           ${ADMIN_KEY}${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
