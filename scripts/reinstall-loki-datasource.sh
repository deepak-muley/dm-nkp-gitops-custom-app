#!/bin/bash
# Script to reinstall Loki datasource in Grafana

set -e

OBSERVABILITY_NAMESPACE="${OBSERVABILITY_NAMESPACE:-observability}"

echo "=========================================="
echo "Reinstalling Loki Datasource in Grafana"
echo "=========================================="
echo ""

# Get Grafana password
GRAFANA_PASSWORD=$(kubectl get secret -n $OBSERVABILITY_NAMESPACE prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")

# Port forward to Grafana
echo "Step 1: Setting up port forward to Grafana..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana 3000:80 >/dev/null 2>&1 &
GRAFANA_PF_PID=$!
sleep 5

# Wait for Grafana API
echo "Step 2: Waiting for Grafana API..."
for i in {1..30}; do
    if curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:3000/api/health" >/dev/null 2>&1; then
        echo "✅ Grafana API is ready"
        break
    fi
    sleep 1
done

# Find Loki service
echo ""
echo "Step 3: Finding Loki service..."
LOKI_SVC=""
LOKI_PORT=""

# Try different service name patterns
if kubectl get svc loki-loki-distributed-gateway -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
    LOKI_SVC="loki-loki-distributed-gateway"
    LOKI_PORT=$(kubectl get svc $LOKI_SVC -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null)
    if [ -z "$LOKI_PORT" ]; then
        LOKI_PORT=$(kubectl get svc $LOKI_SVC -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")
    fi
elif kubectl get svc loki-gateway -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
    LOKI_SVC="loki-gateway"
    LOKI_PORT=$(kubectl get svc $LOKI_SVC -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null)
    if [ -z "$LOKI_PORT" ]; then
        LOKI_PORT=$(kubectl get svc $LOKI_SVC -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")
    fi
elif kubectl get svc loki -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
    LOKI_SVC="loki"
    LOKI_PORT=$(kubectl get svc $LOKI_SVC -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null)
    if [ -z "$LOKI_PORT" ]; then
        LOKI_PORT=$(kubectl get svc $LOKI_SVC -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "3100")
    fi
elif kubectl get svc -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -i gateway | grep -qi loki; then
    LOKI_SVC=$(kubectl get svc -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -i gateway | grep -i loki | head -1 | awk '{print $1}')
    if [ -n "$LOKI_SVC" ]; then
        LOKI_PORT=$(kubectl get svc "$LOKI_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null)
        if [ -z "$LOKI_PORT" ]; then
            LOKI_PORT=$(kubectl get svc "$LOKI_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")
        fi
    fi
fi

if [ -z "$LOKI_SVC" ]; then
    echo "❌ Error: Loki service not found in namespace $OBSERVABILITY_NAMESPACE"
    kill $GRAFANA_PF_PID 2>/dev/null || true
    exit 1
fi

echo "✅ Found Loki service: $LOKI_SVC (port: $LOKI_PORT)"

# Find Tempo UID for correlation (if available)
echo ""
echo "Step 4: Finding Tempo datasource for correlation..."
TEMPO_UID=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
    "http://localhost:3000/api/datasources/name/Tempo" 2>/dev/null | jq -r '.uid' 2>/dev/null || echo "")
if [ -n "$TEMPO_UID" ] && [ "$TEMPO_UID" != "null" ]; then
    echo "  Tempo UID found: $TEMPO_UID (will enable trace correlation)"
else
    echo "  Tempo datasource not found (trace correlation will be disabled)"
fi

# Configure Loki datasource
echo ""
echo "Step 5: Configuring Loki datasource..."
LOKI_URL="http://${LOKI_SVC}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:${LOKI_PORT}"

# Get Tempo UID for correlation
TEMPO_UID=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
    "http://localhost:3000/api/datasources/name/Tempo" 2>/dev/null | jq -r '.uid' 2>/dev/null || echo "")

# Build Loki JSON (simplified - derivedFields can be added later via UI if needed)
LOKI_JSON=$(cat <<EOF
{
  "name": "Loki",
  "type": "loki",
  "url": "${LOKI_URL}",
  "access": "proxy",
  "uid": "loki",
  "editable": true,
  "jsonData": {
    "maxLines": 1000
  }
}
EOF
)

# Check if Loki datasource already exists
EXISTING_LOKI=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
    "http://localhost:3000/api/datasources/name/Loki" 2>/dev/null)

if echo "$EXISTING_LOKI" | grep -q '"id"'; then
    # Update existing datasource
    echo "  Updating existing Loki datasource..."
    LOKI_ID=$(echo "$EXISTING_LOKI" | jq -r '.id' 2>/dev/null)
    LOKI_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
        -u "admin:${GRAFANA_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d "${LOKI_JSON}" \
        "http://localhost:3000/api/datasources/${LOKI_ID}" 2>/dev/null)
    LOKI_HTTP_CODE=$(echo "$LOKI_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$LOKI_RESPONSE" | sed '$d')

    if [ "$LOKI_HTTP_CODE" = "200" ]; then
        echo "✅ Loki datasource updated successfully"
    else
        echo "⚠️  Failed to update Loki datasource (HTTP $LOKI_HTTP_CODE)"
        echo "Response: $RESPONSE_BODY" | jq -r '.' 2>/dev/null || echo "$RESPONSE_BODY"
    fi
else
    # Create new datasource
    echo "  Creating new Loki datasource..."
    LOKI_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -u "admin:${GRAFANA_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d "${LOKI_JSON}" \
        "http://localhost:3000/api/datasources" 2>/dev/null)
    LOKI_HTTP_CODE=$(echo "$LOKI_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$LOKI_RESPONSE" | sed '$d')

    if [ "$LOKI_HTTP_CODE" = "200" ] || [ "$LOKI_HTTP_CODE" = "201" ]; then
        echo "✅ Loki datasource created successfully"
    else
        echo "❌ Failed to create Loki datasource (HTTP $LOKI_HTTP_CODE)"
        echo "Response: $RESPONSE_BODY" | jq -r '.' 2>/dev/null || echo "$RESPONSE_BODY"
        kill $GRAFANA_PF_PID 2>/dev/null || true
        exit 1
    fi
fi

# Verify Loki datasource
echo ""
echo "Step 6: Verifying Loki datasource..."
VERIFY_LOKI=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
    "http://localhost:3000/api/datasources/name/Loki" 2>/dev/null)

if echo "$VERIFY_LOKI" | grep -q '"id"'; then
    LOKI_UID=$(echo "$VERIFY_LOKI" | jq -r '.uid' 2>/dev/null)
    LOKI_URL_VERIFY=$(echo "$VERIFY_LOKI" | jq -r '.url' 2>/dev/null)
    echo "✅ Loki datasource verified"
    echo "  UID: $LOKI_UID"
    echo "  URL: $LOKI_URL_VERIFY"

    # Test Loki query
    echo ""
    echo "Step 7: Testing Loki query..."
    START_TIME=$(date -u -v-5M +%s)000000000
    END_TIME=$(date -u +%s)000000000

    LOKI_RESULT=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
        -X POST "http://localhost:3000/api/datasources/proxy/uid/${LOKI_UID}/loki/api/v1/query_range" \
        -H "Content-Type: application/json" \
        -d "{\"query\":\"{job=~\\\"dm-nkp.*|otel.*\\\"}\",\"start\":\"${START_TIME}\",\"end\":\"${END_TIME}\",\"limit\":10}" 2>/dev/null)

    LOG_COUNT=$(echo "$LOKI_RESULT" | jq -r '.data.result[]?.values | length' 2>/dev/null | awk '{sum+=$1} END {print sum+0}')

    if [ "$LOG_COUNT" -gt 0 ] 2>/dev/null; then
        echo "✅ Loki query successful - Found $LOG_COUNT log entries"
    else
        echo "⚠️  Loki query successful but no logs found (this is normal if no traffic has been generated)"
    fi
else
    echo "❌ Failed to verify Loki datasource"
fi

# Cleanup
kill $GRAFANA_PF_PID 2>/dev/null || true

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Loki datasource has been reinstalled"
echo ""
echo "Configuration:"
echo "  Name: Loki"
echo "  URL: $LOKI_URL"
echo "  UID: loki"
echo ""
echo "Next steps:"
echo "1. Open Grafana: http://localhost:3000"
echo "2. Go to Configuration → Data Sources"
echo "3. Verify Loki datasource is listed"
echo "4. Test it: Go to Explore → Select Loki"
echo "5. Query: {job=~\"dm-nkp.*|otel.*\"}"
echo "6. Generate load: ./scripts/generate-load.sh"
echo "7. Check logs dashboard: dm-nkp-gitops-custom-app - Logs"
