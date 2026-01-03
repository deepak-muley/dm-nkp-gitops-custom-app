#!/bin/bash
set -euo pipefail

# Script to configure Grafana dashboard and Prometheus datasource on any existing cluster
# Usage: ./scripts/setup-grafana-dashboard.sh [grafana-namespace] [grafana-service] [prometheus-url]

GRAFANA_NAMESPACE="${1:-monitoring}"
GRAFANA_SERVICE="${2:-prometheus-grafana}"
PROMETHEUS_URL="${3:-}"
DASHBOARD_FILE="${4:-grafana/dashboard.json}"

echo "=========================================="
echo "  Configuring Grafana Dashboard"
echo "=========================================="
echo "Grafana namespace: $GRAFANA_NAMESPACE"
echo "Grafana service: $GRAFANA_SERVICE"
echo ""

# Check prerequisites
command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl is required but not installed. Aborting." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Error: curl is required but not installed. Aborting." >&2; exit 1; }

# Check if dashboard file exists
if [ ! -f "$DASHBOARD_FILE" ]; then
    echo "Error: Dashboard file not found at $DASHBOARD_FILE"
    echo "Please provide the path to dashboard.json"
    exit 1
fi

# Check if Grafana service exists
if ! kubectl get svc "$GRAFANA_SERVICE" -n "$GRAFANA_NAMESPACE" >/dev/null 2>&1; then
    echo "Error: Grafana service '$GRAFANA_SERVICE' not found in namespace '$GRAFANA_NAMESPACE'"
    echo ""
    echo "Available services in namespace '$GRAFANA_NAMESPACE':"
    kubectl get svc -n "$GRAFANA_NAMESPACE" 2>/dev/null || echo "Namespace '$GRAFANA_NAMESPACE' not found"
    echo ""
    echo "Usage: $0 [grafana-namespace] [grafana-service] [prometheus-url]"
    echo "Example: $0 monitoring prometheus-grafana http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090"
    exit 1
fi

# Wait for Grafana pod to be ready
echo "Waiting for Grafana to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n "$GRAFANA_NAMESPACE" --timeout=2m >/dev/null 2>&1 || {
    echo "Warning: Grafana pod may not be ready, continuing anyway..."
}

# Get Grafana admin password
echo "Retrieving Grafana admin credentials..."
GRAFANA_PASSWORD=$(kubectl get secret -n "$GRAFANA_NAMESPACE" "$GRAFANA_SERVICE" -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || \
    kubectl get secret -n "$GRAFANA_NAMESPACE" grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || \
    echo "admin")

# Detect Grafana port
GRAFANA_PORT=$(kubectl get svc "$GRAFANA_SERVICE" -n "$GRAFANA_NAMESPACE" -o jsonpath="{.spec.ports[0].port}" 2>/dev/null || echo "80")
LOCAL_PORT=3000

# Port forward to Grafana in background
echo "Setting up port-forward to Grafana..."
kubectl port-forward -n "$GRAFANA_NAMESPACE" "svc/$GRAFANA_SERVICE" "$LOCAL_PORT:$GRAFANA_PORT" >/dev/null 2>&1 &
GRAFANA_PF_PID=$!
sleep 3

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up port-forward..."
    kill $GRAFANA_PF_PID 2>/dev/null || true
    wait $GRAFANA_PF_PID 2>/dev/null || true
}
trap cleanup EXIT

# Wait for Grafana API to be ready
echo "Waiting for Grafana API..."
for i in {1..30}; do
    if curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:${LOCAL_PORT}/api/health" >/dev/null 2>&1; then
        echo "✓ Grafana API is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Error: Grafana API not responding after 30 seconds"
        exit 1
    fi
    sleep 1
done

# Auto-detect Prometheus URL if not provided
if [ -z "$PROMETHEUS_URL" ]; then
    echo "Auto-detecting Prometheus URL..."
    # Try common Prometheus service names
    if kubectl get svc prometheus-kube-prometheus-prometheus -n "$GRAFANA_NAMESPACE" >/dev/null 2>&1; then
        PROMETHEUS_URL="http://prometheus-kube-prometheus-prometheus.${GRAFANA_NAMESPACE}.svc.cluster.local:9090"
    elif kubectl get svc prometheus -n "$GRAFANA_NAMESPACE" >/dev/null 2>&1; then
        PROMETHEUS_URL="http://prometheus.${GRAFANA_NAMESPACE}.svc.cluster.local:9090"
    else
        echo "Warning: Could not auto-detect Prometheus service"
        echo "Please provide Prometheus URL manually:"
        echo "  $0 $GRAFANA_NAMESPACE $GRAFANA_SERVICE http://prometheus-service.namespace.svc.cluster.local:9090"
        PROMETHEUS_URL="http://prometheus.${GRAFANA_NAMESPACE}.svc.cluster.local:9090"
    fi
fi

echo "Using Prometheus URL: $PROMETHEUS_URL"
echo ""

# Step 1: Configure Prometheus datasource
echo "Step 1: Configuring Prometheus datasource..."
DATASOURCE_JSON=$(cat <<EOF
{
  "name": "Prometheus",
  "type": "prometheus",
  "url": "${PROMETHEUS_URL}",
  "access": "proxy",
  "isDefault": true,
  "jsonData": {
    "timeInterval": "15s"
  }
}
EOF
)

# Check if datasource already exists
EXISTING_DS=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
    "http://localhost:${LOCAL_PORT}/api/datasources/name/Prometheus" 2>/dev/null)

if echo "$EXISTING_DS" | grep -q '"id"'; then
    # Update existing datasource
    DS_ID=$(echo "$EXISTING_DS" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    DS_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
        -u "admin:${GRAFANA_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d "${DATASOURCE_JSON}" \
        "http://localhost:${LOCAL_PORT}/api/datasources/${DS_ID}" 2>/dev/null)
    DS_HTTP_CODE=$(echo "$DS_RESPONSE" | tail -n1)
    if [ "$DS_HTTP_CODE" = "200" ]; then
        echo "✓ Prometheus datasource updated"
    else
        echo "⚠ Failed to update datasource (HTTP $DS_HTTP_CODE)"
        echo "Response: $(echo "$DS_RESPONSE" | head -n-1)"
    fi
else
    # Create new datasource
    DS_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -u "admin:${GRAFANA_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d "${DATASOURCE_JSON}" \
        "http://localhost:${LOCAL_PORT}/api/datasources" 2>/dev/null)
    DS_HTTP_CODE=$(echo "$DS_RESPONSE" | tail -n1)
    if [ "$DS_HTTP_CODE" = "200" ] || [ "$DS_HTTP_CODE" = "201" ]; then
        echo "✓ Prometheus datasource created"
    else
        echo "⚠ Failed to create datasource (HTTP $DS_HTTP_CODE)"
        echo "Response: $(echo "$DS_RESPONSE" | head -n-1)"
    fi
fi

# Step 2: Import dashboard
echo ""
echo "Step 2: Importing dashboard..."
# Prepare dashboard JSON for import
if command -v jq >/dev/null 2>&1; then
    DASHBOARD_JSON=$(jq -n --argjson dashboard "$(cat "$DASHBOARD_FILE")" '{dashboard: $dashboard, overwrite: true}')
else
    # Fallback: wrap dashboard JSON manually
    DASHBOARD_CONTENT=$(cat "$DASHBOARD_FILE")
    DASHBOARD_JSON="{\"dashboard\":${DASHBOARD_CONTENT},\"overwrite\":true}"
fi

# Import dashboard via API
IMPORT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -u "admin:${GRAFANA_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d "${DASHBOARD_JSON}" \
    "http://localhost:${LOCAL_PORT}/api/dashboards/db" 2>/dev/null)

HTTP_CODE=$(echo "$IMPORT_RESPONSE" | tail -n1)
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ Dashboard imported successfully"
    DASHBOARD_IMPORTED=true
else
    echo "⚠ Dashboard import failed (HTTP $HTTP_CODE)"
    echo "Response: $(echo "$IMPORT_RESPONSE" | head -n-1)"
    DASHBOARD_IMPORTED=false
fi

# Summary
echo ""
echo "=========================================="
echo "  Configuration Complete!"
echo "=========================================="
echo ""
if [ "${DASHBOARD_IMPORTED:-false}" = "true" ]; then
    echo "✅ Prometheus datasource configured"
    echo "✅ Dashboard imported"
    echo ""
    echo "📊 Access Grafana:"
    echo "   kubectl port-forward -n $GRAFANA_NAMESPACE svc/$GRAFANA_SERVICE $LOCAL_PORT:$GRAFANA_PORT"
    echo "   http://localhost:$LOCAL_PORT"
    echo "   Username: admin"
    echo "   Password: $GRAFANA_PASSWORD"
    echo ""
    echo "📈 Navigate to dashboard:"
    echo "   Dashboards → dm-nkp-gitops-custom-app Metrics"
else
    echo "⚠ Some steps may have failed. Check the output above."
    echo ""
    echo "You can manually import the dashboard:"
    echo "   1. Port forward: kubectl port-forward -n $GRAFANA_NAMESPACE svc/$GRAFANA_SERVICE $LOCAL_PORT:$GRAFANA_PORT"
    echo "   2. Open: http://localhost:$LOCAL_PORT"
    echo "   3. Login: admin / $GRAFANA_PASSWORD"
    echo "   4. Import: Dashboards → Import → Upload $DASHBOARD_FILE"
fi
echo ""

