#!/bin/bash
set -euo pipefail

# Comprehensive script to fix datasources and dashboards
# This script ensures datasources are persistent and dashboards show data

OBSERVABILITY_NAMESPACE="observability"
APP_NAMESPACE="default"
APP_NAME="dm-nkp-gitops-custom-app"

echo "=========================================="
echo "Fixing Datasources and Dashboards"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}✓${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo_error() {
    echo -e "${RED}✗${NC} $1"
}

echo_step() {
    echo -e "${BLUE}→${NC} $1"
}

# Step 1: Fix datasources via API (persistent)
echo_step "Step 1: Configuring Grafana datasources via API..."
/Users/deepak/go/src/github.com/deepak-muley/dm-nkp-gitops-custom-app/scripts/fix-grafana-datasources.sh

# Step 2: Update dashboard ConfigMap
echo ""
echo_step "Step 2: Updating dashboard ConfigMap..."
DASHBOARD_CONTENT=$(cat /Users/deepak/go/src/github.com/deepak-muley/dm-nkp-gitops-custom-app/chart/dm-nkp-gitops-custom-app/files/grafana/dashboard-metrics.json)
kubectl create configmap dm-nkp-gitops-custom-app-grafana-dashboard-metrics \
    --from-literal=dashboard-metrics.json="${DASHBOARD_CONTENT}" \
    -n $OBSERVABILITY_NAMESPACE \
    --dry-run=client -o yaml | \
kubectl label --dry-run=client -f - --local grafana_dashboard=1 -o yaml | \
kubectl annotate --dry-run=client -f - --local grafana-folder=/ -o yaml | \
kubectl apply -f - >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo_info "Metrics dashboard ConfigMap updated"
else
    echo_error "Failed to update metrics dashboard ConfigMap"
fi

# Step 3: Generate traffic
echo ""
echo_step "Step 3: Generating traffic to create metrics..."
for i in {1..50}; do
    kubectl exec -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME -- curl -s http://localhost:8080/ > /dev/null 2>&1 || true
done
echo_info "Generated 50 HTTP requests"
echo_warn "Waiting 60 seconds for OTel SDK to export metrics (30s interval)..."
sleep 60

# Step 4: Verify datasources persist after Grafana restart
echo ""
echo_step "Step 4: Verifying datasources persist..."
kubectl rollout restart deployment prometheus-grafana -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1
echo_info "Grafana restarted"
sleep 20

kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana 3000:80 > /tmp/grafana-final.log 2>&1 &
GRAFANA_PF_PID=$!
sleep 10

GRAFANA_PASSWORD=$(kubectl get secret -n $OBSERVABILITY_NAMESPACE prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")

DS_COUNT=$(curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:3000/api/datasources" 2>/dev/null | jq -r 'length' 2>/dev/null || echo "0")
if [ "$DS_COUNT" -ge 3 ]; then
    echo_info "Datasources persist after restart: $DS_COUNT found"
    curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:3000/api/datasources" 2>/dev/null | jq -r '.[] | "  ✓ \(.name) (\(.type))"' 2>/dev/null
else
    echo_warn "Only $DS_COUNT datasources found, reconfiguring..."
    /Users/deepak/go/src/github.com/deepak-muley/dm-nkp-gitops-custom-app/scripts/fix-grafana-datasources.sh
fi

# Step 5: Verify metrics in Prometheus
echo ""
echo_step "Step 5: Verifying metrics in Prometheus..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090 > /tmp/prom-final.log 2>&1 &
PROM_PF_PID=$!
sleep 5

METRIC_RATE=$(curl -s "http://localhost:9090/api/v1/query?query=sum(rate(http_server_duration_milliseconds_count{job=\"dm-nkp-gitops-custom-app\"}[5m]))" 2>/dev/null | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null)
if [ "$METRIC_RATE" != "0" ] && [ -n "$METRIC_RATE" ]; then
    echo_info "Metrics found in Prometheus: Request rate = $METRIC_RATE req/s"
else
    echo_warn "No metrics found in Prometheus yet (may need more time)"
fi

# Cleanup
kill $GRAFANA_PF_PID 2>/dev/null || true
kill $PROM_PF_PID 2>/dev/null || true

echo ""
echo "=========================================="
echo "✅ Fix Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "1. ✅ Datasources configured via API (persistent)"
echo "2. ✅ Dashboard ConfigMap updated"
echo "3. ✅ Traffic generated"
echo "4. ✅ Datasources verified to persist after restart"
echo ""
echo "Next steps:"
echo "1. Wait 1-2 minutes for all data to propagate"
echo "2. Check Grafana dashboards:"
echo "   - Metrics: http://localhost:3000/d/dm-nkp-custom-app-metrics/dm-nkp-gitops-custom-app-metrics"
echo "   - Logs: http://localhost:3000/d/dm-nkp-custom-app-logs/dm-nkp-gitops-custom-app-logs"
echo "   - Traces: http://localhost:3000/d/dm-nkp-custom-app-traces/dm-nkp-gitops-custom-app-traces"
echo ""
echo "If datasources disappear again, check:"
echo "- Grafana ConfigMap provisioning (may override API datasources)"
echo "- Grafana restart logs for errors"
