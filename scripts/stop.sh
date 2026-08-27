#!/usr/bin/env bash
# ============================================================
#  APISIX Local Stack - Stop Script (Linux/macOS)
# ============================================================
echo "Stopping APISIX stack..."
docker compose down
echo "✅ All services stopped. Data volumes preserved."
echo "To remove volumes too: docker compose down -v"
