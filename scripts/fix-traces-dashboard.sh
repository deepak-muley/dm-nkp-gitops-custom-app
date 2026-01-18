#!/bin/bash
# Script to fix traces dashboard in Grafana

set -e

OBSERVABILITY_NAMESPACE="${OBSERVABILITY_NAMESPACE:-observability}"
DASHBOARD_NAME="dm-nkp-gitops-custom-app - Traces"
DASHBOARD_UID="dm-nkp-custom-app-traces"

echo "=========================================="
echo "Fixing Traces Dashboard"
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

# Get dashboard
echo ""
echo "Step 3: Getting current dashboard..."
DASHBOARD_JSON=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
    "http://localhost:3000/api/dashboards/uid/${DASHBOARD_UID}" 2>/dev/null)

if [ -z "$DASHBOARD_JSON" ] || echo "$DASHBOARD_JSON" | grep -q "Dashboard not found"; then
    echo "⚠️  Dashboard not found, will import from file"
    DASHBOARD_JSON=""
else
    echo "✅ Dashboard found"
fi

# Update dashboard from file
echo ""
echo "Step 4: Updating dashboard from file..."
DASHBOARD_FILE="chart/dm-nkp-gitops-custom-app/files/grafana/dashboard-traces.json"

if [ ! -f "$DASHBOARD_FILE" ]; then
    echo "❌ Error: Dashboard file not found: $DASHBOARD_FILE"
    kill $GRAFANA_PF_PID 2>/dev/null || true
    exit 1
fi

# Read dashboard JSON
DASHBOARD_CONTENT=$(cat "$DASHBOARD_FILE")

# Import/update dashboard
echo "Importing/updating dashboard..."
IMPORT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -u "admin:${GRAFANA_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d "{\"dashboard\":${DASHBOARD_CONTENT},\"overwrite\":true}" \
    "http://localhost:3000/api/dashboards/db" 2>/dev/null)

HTTP_CODE=$(echo "$IMPORT_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$IMPORT_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo "✅ Dashboard updated successfully"
else
    echo "⚠️  Dashboard update returned HTTP $HTTP_CODE"
    echo "Response: $RESPONSE_BODY" | jq -r '.' 2>/dev/null || echo "$RESPONSE_BODY"
fi

# Verify Tempo datasource
echo ""
echo "Step 5: Verifying Tempo datasource..."
TEMPO_DS=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
    "http://localhost:3000/api/datasources/name/Tempo" 2>/dev/null)

TEMPO_UID=$(echo "$TEMPO_DS" | jq -r '.uid' 2>/dev/null || echo "")

if [ -n "$TEMPO_UID" ] && [ "$TEMPO_UID" != "null" ]; then
    echo "✅ Tempo datasource found (UID: $TEMPO_UID)"

    # Test Tempo query
    echo "Testing Tempo query..."
    TEMPO_RESULT=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
        "http://localhost:3000/api/datasources/proxy/uid/${TEMPO_UID}/api/search?limit=5" 2>/dev/null)

    TRACE_COUNT=$(echo "$TEMPO_RESULT" | jq -r '.traces | length' 2>/dev/null || echo "0")
    echo "  Traces found: $TRACE_COUNT"

    if [ "$TRACE_COUNT" -gt 0 ]; then
        echo "  Sample trace IDs:"
        echo "$TEMPO_RESULT" | jq -r '.traces[]?.traceID' 2>/dev/null | head -3 | while read trace_id; do
            echo "    - $trace_id"
        done
    fi
else
    echo "⚠️  Tempo datasource not found or UID is null"
    echo "Response: $TEMPO_DS" | jq -r '.' 2>/dev/null || echo "$TEMPO_DS"
fi

# Cleanup
kill $GRAFANA_PF_PID 2>/dev/null || true

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Dashboard: $DASHBOARD_NAME"
echo "UID: $DASHBOARD_UID"
echo ""
echo "Next steps:"
echo "1. Open Grafana: http://localhost:3000"
echo "2. Navigate to: Dashboards → $DASHBOARD_NAME"
echo "3. Check if traces are displaying"
echo "4. If not, verify:"
echo "   - Tempo datasource is configured correctly"
echo "   - Traces exist in Tempo (run: ./scripts/verify-logs-traces.sh)"
echo "   - Service name matches: dm-nkp-gitops-custom-app"
