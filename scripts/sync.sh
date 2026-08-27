#!/usr/bin/env bash
# ==============================================================================
# 🏛️ Qyadati APISIX Local GitOps Sync CLI Shortcut (Linux/macOS)
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/sync-gateway.py" "$@"
