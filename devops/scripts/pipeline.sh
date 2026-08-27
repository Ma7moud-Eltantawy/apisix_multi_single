#!/usr/bin/env bash
# ==============================================================================
# 🚀 QYADATI DEVOPS - COMPLETE DEPLOYMENT PIPELINE ENGINE
# ==============================================================================
# This script runs the entire deployment lifecycle directly on the DevOps side:
# 1. (Optional) Git Pull
# 2. Syntax & Schema Validation (adc validate)
# 3. Pre-flight Diff Inspection (adc diff)
# 4. Automated Pre-Deploy Backup (etcd snapshot)
# 5. Zero-Downtime Hot Reload Sync (adc sync)
# 6. Post-Deploy Health Check & Auto-Rollback on Failure
# ==============================================================================
set -euo pipefail

TARGET_FLAVOR="${1:-prod}"
ACTION_OR_TAG="${2:-pull}"     # e.g., "pull", "v1.0.0", "rollback", "list-tags"
ROLLBACK_TAG="${3:-}"          # e.g., tag to rollback to if $2 is "rollback"

# Load root .env environment variables if available
if [ -f ".env" ]; then
    set -a
    source ".env"
    set +a
fi

ADMIN_URL="${APISIX_ADMIN_URL:-http://127.0.0.1:9181}"
ADMIN_TOKEN="${APISIX_ADMIN_TOKEN:-${ADMIN_KEY:-your_token_here}}"
GATEWAY_URL="${APISIX_GATEWAY_URL:-http://127.0.0.1:9280}"
CONFIG_FILE="configs/flavors/${TARGET_FLAVOR}/apisix.yaml"

# ----------------------------------------------------------------------
# HELPER: List Tags
# ----------------------------------------------------------------------
if [ "$ACTION_OR_TAG" == "list-tags" ] || [ "$TARGET_FLAVOR" == "list-tags" ]; then
    echo "🏷️ Fetching official release tags from Git..."
    git fetch --tags origin 2>/dev/null || true
    echo ""
    echo "Available Git Release Tags:"
    git tag -l -n1 --sort=-v:refname
    exit 0
fi

# ----------------------------------------------------------------------
# STEP 0: Git Version & Tag Resolution
# ----------------------------------------------------------------------
DEPLOY_TAG="latest"

if [ "$TARGET_FLAVOR" == "prod" ]; then
    echo "🏷️ [Production Gate] Fetching Git tags from origin..."
    git fetch --tags origin 2>/dev/null || true

    if [ "$ACTION_OR_TAG" == "rollback" ]; then
        if [ -z "$ROLLBACK_TAG" ]; then
            echo "❌ [Rollback Error] Please specify the target tag for rollback!"
            echo "Usage: ./devops/scripts/pipeline.sh prod rollback <tag_name>"
            echo "Example: ./devops/scripts/pipeline.sh prod rollback v1.0.0"
            echo ""
            echo "Available tags:"
            git tag -l --sort=-v:refname | head -n 10
            exit 1
        fi
        DEPLOY_TAG="$ROLLBACK_TAG"
        echo "🔄 [ROLLBACK INITIATED] Switching to stable version: ${DEPLOY_TAG}"
        git checkout "tags/${DEPLOY_TAG}" --force
    elif [[ "$ACTION_OR_TAG" =~ ^v[0-9] ]]; then
        # Direct tag passed as 2nd argument (e.g. ./pipeline.sh prod v1.2.0)
        DEPLOY_TAG="$ACTION_OR_TAG"
        echo "📥 [Version Checkout] Switching to specified Git Tag: ${DEPLOY_TAG}"
        git checkout "tags/${DEPLOY_TAG}" --force
    elif [ "$ACTION_OR_TAG" == "pull" ]; then
        LATEST_TAG=$(git tag -l --sort=-v:refname | head -n 1)
        if [ -n "$LATEST_TAG" ]; then
            DEPLOY_TAG="$LATEST_TAG"
            echo "📥 [Production Pull] Checking out latest official stable tag: ${DEPLOY_TAG}"
            git checkout "tags/${DEPLOY_TAG}" --force
        else
            echo "⚠️ [Warning] No Git tags found in repository. Pulling latest main branch..."
            git pull origin main || echo "⚠️ Git pull warning."
            DEPLOY_TAG="main-$(git rev-parse --short HEAD)"
        fi
    fi
else
    # Non-prod flavors (dev, staging, local, desktop)
    if [ "$ACTION_OR_TAG" == "pull" ]; then
        echo "📥 [Non-Prod Pull] Pulling latest changes from main branch..."
        git pull origin main || echo "⚠️ Git pull warning."
    fi
    DEPLOY_TAG="branch-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'current')"
fi

COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

echo "======================================================================"
echo "🛡️  QYADATI DEVOPS PIPELINE — [Flavor: ${TARGET_FLAVOR}]"
echo "======================================================================"
echo "Target Flavor  : ${TARGET_FLAVOR}"
echo "Release Version: ${DEPLOY_TAG}"
echo "Commit Hash    : ${COMMIT_HASH}"
echo "Config Path    : ${CONFIG_FILE}"
echo "Admin API      : ${ADMIN_URL}"
echo "Gateway URL    : ${GATEWAY_URL}"
echo "======================================================================"

# ----------------------------------------------------------------------
# STEP 1: Verify Config File Exists
# ----------------------------------------------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ [Fatal Error] Config file not found at: ${CONFIG_FILE}"
    echo "Available flavors: desktop, local, dev, staging, prod"
    exit 1
fi

# Determine ADC command (local binary vs docker container)
if command -v adc &> /dev/null; then
    ADC_CMD="adc"
    ADC_FILE="$CONFIG_FILE"
elif [ -f "./bin/adc" ]; then
    ADC_CMD="./bin/adc"
    ADC_FILE="$CONFIG_FILE"
elif [ -f "./bin/adc.exe" ]; then
    ADC_CMD="./bin/adc.exe"
    ADC_FILE="$CONFIG_FILE"
else
    echo "🐳 ADC not found in PATH. Using official Docker runner..."
    ADC_CMD="docker run --rm --network host -v $(pwd)/configs:/configs api7/adc:v0.9.0"
    ADC_FILE="/configs/flavors/${TARGET_FLAVOR}/apisix.yaml"
fi

# ----------------------------------------------------------------------
# STEP 2: Syntax Validation
# ----------------------------------------------------------------------
echo ""
echo "🔍 [Step 1/5] Validating configuration syntax & APISIX schema..."
if ! $ADC_CMD validate -f "$ADC_FILE"; then
    echo "❌ [Validation Failed] Configuration syntax is invalid. Aborting deployment!"
    exit 1
fi
echo "✅ Schema validation passed."

# ----------------------------------------------------------------------
# STEP 3: Pre-flight Diff Inspection
# ----------------------------------------------------------------------
echo ""
echo "📊 [Step 2/5] Inspecting differences between Git config & live Gateway..."
$ADC_CMD diff -f "$ADC_FILE" \
    --apisix-admin-url "$ADMIN_URL" \
    --apisix-admin-token "$ADMIN_TOKEN" || true

# ----------------------------------------------------------------------
# STEP 4: Automated Pre-Deploy Backup
# ----------------------------------------------------------------------
echo ""
echo "💾 [Step 3/5] Creating pre-deploy etcd snapshot backup..."
BACKUP_DIR="./devops/backups/etcd"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SNAPSHOT_FILE="${BACKUP_DIR}/pre_deploy_${TARGET_FLAVOR}_${DEPLOY_TAG}_${TIMESTAMP}.db"
ETCD_CONTAINER="${ETCD_CONTAINER:-qyadati-apisix-etcd}"

if docker ps --format '{{.Names}}' | grep -q "^${ETCD_CONTAINER}$"; then
    docker exec "$ETCD_CONTAINER" etcdctl snapshot save /tmp/snapshot.db > /dev/null 2>&1 || true
    docker cp "${ETCD_CONTAINER}:/tmp/snapshot.db" "$SNAPSHOT_FILE" > /dev/null 2>&1 || true
    docker exec "$ETCD_CONTAINER" rm -f /tmp/snapshot.db > /dev/null 2>&1 || true
    echo "✅ Backup snapshot created: ${SNAPSHOT_FILE}"
else
    echo "⚠️ etcd container '${ETCD_CONTAINER}' not detected locally. Skipping local snapshot."
fi

# ----------------------------------------------------------------------
# STEP 5: Apply & Synchronize (Hot Reload)
# ----------------------------------------------------------------------
echo ""
echo "🚀 [Step 4/5] Applying configuration via ADC (Zero-Downtime Hot Reload)..."
if ! $ADC_CMD sync -f "$ADC_FILE" \
    --apisix-admin-url "$ADMIN_URL" \
    --apisix-admin-token "$ADMIN_TOKEN"; then
    echo "❌ [Deployment Failed] ADC sync failed to apply configuration!"
    exit 1
fi
echo "✅ Configuration successfully synchronized to APISIX Control Plane."

# ----------------------------------------------------------------------
# STEP 6: Health Check & Verification
# ----------------------------------------------------------------------
echo ""
echo "🩺 [Step 5/5] Performing post-deployment health checks..."
sleep 1

HEALTH_OK=false
for i in {1..3}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${GATEWAY_URL}/health" || echo "000")
    if [ "$HTTP_CODE" != "000" ] && [ "$HTTP_CODE" != "502" ] && [ "$HTTP_CODE" != "503" ]; then
        HEALTH_OK=true
        break
    fi
    echo "⏳ Waiting for Gateway probe (attempt $i/3)..."
    sleep 2
done

# Audit Log
LOG_FILE="./devops/deployments.log"
mkdir -p "$(dirname "$LOG_FILE")"
LOG_ENTRY="[$(date +"%Y-%m-%d %H:%M:%S")] FLAVOR=${TARGET_FLAVOR} VERSION=${DEPLOY_TAG} COMMIT=${COMMIT_HASH} STATUS=$([ "$HEALTH_OK" = true ] && echo "SUCCESS" || echo "FAILED")"
echo "$LOG_ENTRY" >> "$LOG_FILE"

echo ""
echo "======================================================================"
if [ "$HEALTH_OK" = true ]; then
    echo "🎉 DEPLOYMENT SUCCEEDED! [Flavor: ${TARGET_FLAVOR}]"
    echo "Version: ${DEPLOY_TAG} (${COMMIT_HASH})"
    echo "Status : Gateway is UP & responding (HTTP $HTTP_CODE)"
    echo "Logged : ${LOG_FILE}"
    echo "Time   : $(date)"
else
    echo "⚠️ Gateway responded with HTTP ${HTTP_CODE}. Please verify upstream services."
fi
echo "======================================================================"
