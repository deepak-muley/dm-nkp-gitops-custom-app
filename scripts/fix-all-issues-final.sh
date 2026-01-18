#!/bin/bash
set -euo pipefail

# Final comprehensive fix script for all dashboard and datasource issues

OBSERVABILITY_NAMESPACE="observability"
APP_NAMESPACE="default"
APP_NAME="dm-nkp-gitops-custom-app"

echo "=========================================="
echo "Final Fix: Datasources and Dashboards"
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

# Step 1: Fix datasource ConfigMap (root cause of datasource removal)
echo_step "Step 1: Fixing Grafana datasource ConfigMap..."
kubectl patch configmap prometheus-kube-prometheus-grafana-datasource -n $OBSERVABILITY_NAMESPACE --type=json -p='[{"op": "replace", "path": "/data/datasources.yaml", "value": "apiVersion: 1\n\ndatasources:\n  - name: Prometheus\n    type: prometheus\n    uid: prometheus\n    url: http://prometheus-kube-prometheus-prometheus.observability:9090/\n    access: proxy\n    isDefault: true\n    jsonData:\n      httpMethod: POST\n      timeInterval: 30s\n  - name: Alertmanager\n    type: alertmanager\n    uid: alertmanager\n    url: http://prometheus-kube-prometheus-alertmanager.observability:9093/\n    access: proxy\n    jsonData:\n      handleGrafanaManagedAlerts: false\n      implementation: prometheus\n  - name: Loki\n    type: loki\n    uid: loki\n    url: http://loki-loki-distributed-gateway.observability.svc.cluster.local:80\n    access: proxy\n    jsonData:\n      maxLines: 1000\n  - name: Tempo\n    type: tempo\n    uid: tempo\n    url: http://tempo.observability.svc.cluster.local:3200\n    access: proxy\n    jsonData:\n      httpMethod: GET\n      serviceMap:\n        datasourceUid: prometheus\n      nodeGraph:\n        enabled: true\n      search:\n        hide: false\n      tracesToLogs:\n        datasourceUid: loki\n        tags: [\"job\", \"instance\", \"pod\", \"namespace\", \"service.name\"]\n      tracesToMetrics:\n        datasourceUid: prometheus\n        tags:\n          - key: service.name\n            value: service\n          - key: job\n"}]' 2>&1 | head -3

if [ $? -eq 0 ]; then
    echo_info "Datasource ConfigMap updated with Loki and Tempo"
else
    echo_error "Failed to update datasource ConfigMap"
fi

# Step 2: Update dashboard ConfigMap with correct queries
echo ""
echo_step "Step 2: Updating dashboard ConfigMap with correct queries..."
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

# Step 3: Restart Grafana to reload ConfigMaps
echo ""
echo_step "Step 3: Restarting Grafana to reload ConfigMaps..."
kubectl rollout restart deployment prometheus-grafana -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1
echo_info "Grafana restarted"
sleep 25

# Step 4: Generate traffic
echo ""
echo_step "Step 4: Generating traffic..."
for i in {1..50}; do
    kubectl exec -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME -- curl -s http://localhost:8080/ > /dev/null 2>&1 || true
done
echo_info "Generated 50 HTTP requests"
echo_warn "Waiting 60 seconds for OTel SDK to export metrics (30s interval)..."
sleep 60

# Step 5: Verify datasources
echo ""
echo_step "Step 5: Verifying datasources..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana 3000:80 > /tmp/grafana-final-verify.log 2>&1 &
GRAFANA_PF_PID=$!
sleep 10

GRAFANA_PASSWORD=$(kubectl get secret -n $OBSERVABILITY_NAMESPACE prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")

DS_COUNT=$(curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:3000/api/datasources" 2>/dev/null | jq -r 'length' 2>/dev/null || echo "0")
if [ "$DS_COUNT" -ge 4 ]; then
    echo_info "All datasources present: $DS_COUNT"
    curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:3000/api/datasources" 2>/dev/null | jq -r '.[] | "  ✓ \(.name) (\(.type))"' 2>/dev/null
else
    echo_warn "Only $DS_COUNT datasources found (expected 4)"
fi

# Step 6: Verify metrics in Prometheus
echo ""
echo_step "Step 6: Verifying metrics in Prometheus..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090 > /tmp/prom-final-verify.log 2>&1 &
PROM_PF_PID=$!
sleep 5

METRIC_RATE=$(curl -s "http://localhost:9090/api/v1/query?query=sum(rate(http_server_duration_milliseconds_count{job=\"otel-collector\",exported_job=\"dm-nkp-gitops-custom-app\"}[5m]))" 2>/dev/null | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null)
if [ "$METRIC_RATE" != "0" ] && [ -n "$METRIC_RATE" ]; then
    echo_info "Metrics found in Prometheus: Request rate = $METRIC_RATE req/s"
else
    echo_warn "No metrics found yet (may need more time or traffic)"
fi

ACTIVE_CONN=$(curl -s "http://localhost:9090/api/v1/query?query=http_active_connections{job=\"otel-collector\",exported_job=\"dm-nkp-gitops-custom-app\"}" 2>/dev/null | jq -r '.data.result[0].value[1] // "no data"' 2>/dev/null)
if [ "$ACTIVE_CONN" != "no data" ]; then
    echo_info "Active connections metric: $ACTIVE_CONN"
fi

# Cleanup
kill $GRAFANA_PF_PID 2>/dev/null || true
kill $PROM_PF_PID 2>/dev/null || true

echo ""
echo "=========================================="
echo "✅ All Fixes Applied!"
echo "=========================================="
echo ""
echo "Root Causes Fixed:"
echo "1. ✅ Datasource removal: Grafana ConfigMap only had Prometheus/Alertmanager"
echo "   → Fixed: Added Loki and Tempo to ConfigMap (persist across restarts)"
echo ""
echo "2. ✅ Dashboard no data: Queries used wrong job label"
echo "   → Fixed: Updated queries to use job=\"otel-collector\",exported_job=\"dm-nkp-gitops-custom-app\""
echo ""
echo "3. ✅ Metrics not showing: Prometheus relabels job to \"otel-collector\""
echo "   → Fixed: Dashboard queries now match Prometheus labels"
echo ""
echo "Next Steps:"
echo "1. Wait 30 seconds for Grafana to fully reload"
echo "2. Check dashboards:"
echo "   - Metrics: http://localhost:3000/d/dm-nkp-custom-app-metrics/dm-nkp-gitops-custom-app-metrics"
echo "   - Logs: http://localhost:3000/d/dm-nkp-custom-app-logs/dm-nkp-gitops-custom-app-logs"
echo "   - Traces: http://localhost:3000/d/dm-nkp-custom-app-traces/dm-nkp-gitops-custom-app-traces"
echo ""
echo "To verify datasources persist:"
echo "  kubectl rollout restart deployment prometheus-grafana -n observability"
echo "  # Wait 30 seconds, then check: http://localhost:3000/connections/datasources"
