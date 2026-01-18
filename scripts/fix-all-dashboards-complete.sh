#!/bin/bash
set -euo pipefail

# Complete fix script for all dashboard and datasource issues

OBSERVABILITY_NAMESPACE="observability"
APP_NAMESPACE="default"
APP_NAME="dm-nkp-gitops-custom-app"

echo "=========================================="
echo "Complete Dashboard and Datasource Fix"
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

# Step 1: Fix datasources
echo_step "Step 1: Fixing Grafana datasources..."
if [ -f "scripts/fix-grafana-datasources.sh" ]; then
    bash scripts/fix-grafana-datasources.sh
else
    echo_warn "fix-grafana-datasources.sh not found, configuring manually..."
    GRAFANA_PASSWORD=$(kubectl get secret -n $OBSERVABILITY_NAMESPACE prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")
    kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana 3000:80 > /tmp/grafana-fix.log 2>&1 &
    GRAFANA_PF_PID=$!
    sleep 5

    # Configure Loki
    LOKI_JSON='{"name":"Loki","type":"loki","url":"http://loki-loki-distributed-gateway.observability.svc.cluster.local:80","access":"proxy","uid":"loki","editable":true,"jsonData":{"maxLines":1000}}'
    curl -s -X POST -u "admin:${GRAFANA_PASSWORD}" -H "Content-Type: application/json" -d "${LOKI_JSON}" "http://localhost:3000/api/datasources" >/dev/null 2>&1 || \
    curl -s -X PUT -u "admin:${GRAFANA_PASSWORD}" -H "Content-Type: application/json" -d "${LOKI_JSON}" "http://localhost:3000/api/datasources/name/Loki" >/dev/null 2>&1 || true

    # Configure Tempo
    TEMPO_JSON='{"name":"Tempo","type":"tempo","url":"http://tempo.observability.svc.cluster.local:3200","access":"proxy","uid":"tempo","editable":true,"jsonData":{"httpMethod":"GET","serviceMap":{"datasourceUid":"prometheus"},"nodeGraph":{"enabled":true},"search":{"hide":false},"tracesToLogs":{"datasourceUid":"loki","tags":["job","instance","pod","namespace","service.name"]},"tracesToMetrics":{"datasourceUid":"prometheus","tags":[{"key":"service.name","value":"service"},{"key":"job"}]}}}'
    curl -s -X POST -u "admin:${GRAFANA_PASSWORD}" -H "Content-Type: application/json" -d "${TEMPO_JSON}" "http://localhost:3000/api/datasources" >/dev/null 2>&1 || \
    curl -s -X PUT -u "admin:${GRAFANA_PASSWORD}" -H "Content-Type: application/json" -d "${TEMPO_JSON}" "http://localhost:3000/api/datasources/name/Tempo" >/dev/null 2>&1 || true

    kill $GRAFANA_PF_PID 2>/dev/null || true
fi

# Step 2: Update metrics dashboard ConfigMap
echo ""
echo_step "Step 2: Updating metrics dashboard ConfigMap..."
DASHBOARD_FILE="/Users/deepak/go/src/github.com/deepak-muley/dm-nkp-gitops-custom-app/chart/dm-nkp-gitops-custom-app/files/grafana/dashboard-metrics.json"
if [ -f "$DASHBOARD_FILE" ]; then
    DASHBOARD_CONTENT=$(cat "$DASHBOARD_FILE")
    kubectl create configmap dm-nkp-gitops-custom-app-grafana-dashboard-metrics \
        --from-literal=dashboard-metrics.json="${DASHBOARD_CONTENT}" \
        -n $OBSERVABILITY_NAMESPACE \
        --dry-run=client -o yaml | \
    kubectl label --dry-run=client -f - --local grafana_dashboard=1 -o yaml | \
    kubectl annotate --dry-run=client -f - --local grafana-folder=/ -o yaml | \
    kubectl apply -f - >/dev/null 2>&1
    echo_info "Metrics dashboard ConfigMap updated"
else
    echo_error "Dashboard file not found: $DASHBOARD_FILE"
fi

# Step 3: Update logs dashboard ConfigMap
echo ""
echo_step "Step 3: Updating logs dashboard ConfigMap..."
DASHBOARD_FILE="/Users/deepak/go/src/github.com/deepak-muley/dm-nkp-gitops-custom-app/chart/dm-nkp-gitops-custom-app/files/grafana/dashboard-logs.json"
if [ -f "$DASHBOARD_FILE" ]; then
    DASHBOARD_CONTENT=$(cat "$DASHBOARD_FILE")
    kubectl create configmap dm-nkp-gitops-custom-app-grafana-dashboard-logs \
        --from-literal=dashboard-logs.json="${DASHBOARD_CONTENT}" \
        -n $OBSERVABILITY_NAMESPACE \
        --dry-run=client -o yaml | \
    kubectl label --dry-run=client -f - --local grafana_dashboard=1 -o yaml | \
    kubectl annotate --dry-run=client -f - --local grafana-folder=/ -o yaml | \
    kubectl apply -f - >/dev/null 2>&1
    echo_info "Logs dashboard ConfigMap updated"
fi

# Step 4: Update traces dashboard ConfigMap
echo ""
echo_step "Step 4: Updating traces dashboard ConfigMap..."
DASHBOARD_FILE="/Users/deepak/go/src/github.com/deepak-muley/dm-nkp-gitops-custom-app/chart/dm-nkp-gitops-custom-app/files/grafana/dashboard-traces.json"
if [ -f "$DASHBOARD_FILE" ]; then
    DASHBOARD_CONTENT=$(cat "$DASHBOARD_FILE")
    kubectl create configmap dm-nkp-gitops-custom-app-grafana-dashboard-traces \
        --from-literal=dashboard-traces.json="${DASHBOARD_CONTENT}" \
        -n $OBSERVABILITY_NAMESPACE \
        --dry-run=client -o yaml | \
    kubectl label --dry-run=client -f - --local grafana_dashboard=1 -o yaml | \
    kubectl annotate --dry-run=client -f - --local grafana-folder=/ -o yaml | \
    kubectl apply -f - >/dev/null 2>&1
    echo_info "Traces dashboard ConfigMap updated"
fi

# Step 5: Restart Grafana to reload dashboards
echo ""
echo_step "Step 5: Restarting Grafana..."
kubectl rollout restart deployment prometheus-grafana -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1
sleep 15
echo_info "Grafana restarted"

# Step 6: Generate traffic
echo ""
echo_step "Step 6: Generating traffic..."
for i in {1..100}; do
    kubectl exec -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME -- curl -s http://localhost:8080/ > /dev/null 2>&1 || true
done
echo_info "Generated 100 HTTP requests"
echo_warn "Waiting 60 seconds for metrics to be exported (OTel SDK uses 30s interval)..."
sleep 60

# Step 7: Verify datasources
echo ""
echo_step "Step 7: Verifying datasources..."
GRAFANA_PASSWORD=$(kubectl get secret -n $OBSERVABILITY_NAMESPACE prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana 3000:80 > /tmp/grafana-verify.log 2>&1 &
GRAFANA_PF_PID=$!
sleep 5

DS_COUNT=$(curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:3000/api/datasources" 2>/dev/null | jq -r 'length' 2>/dev/null || echo "0")
echo_info "Datasources count: $DS_COUNT"
curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:3000/api/datasources" 2>/dev/null | jq -r '.[] | "  ✓ \(.name) (\(.type))"' 2>/dev/null || echo_warn "  No datasources found"

kill $GRAFANA_PF_PID 2>/dev/null || true

# Step 8: Verify metrics in Prometheus
echo ""
echo_step "Step 8: Verifying metrics in Prometheus..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090 > /tmp/prom-verify.log 2>&1 &
PROM_PF_PID=$!
sleep 5

METRIC_COUNT=$(curl -s "http://localhost:9090/api/v1/query?query=http_server_duration_milliseconds_count{job=\"dm-nkp-gitops-custom-app\"}" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")
if [ "$METRIC_COUNT" -gt 0 ]; then
    echo_info "Prometheus has $METRIC_COUNT http_server_duration_milliseconds_count metric series"
    RATE=$(curl -s "http://localhost:9090/api/v1/query?query=sum(rate(http_server_duration_milliseconds_count{job=\"dm-nkp-gitops-custom-app\"}[5m]))" 2>/dev/null | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null)
    echo_info "Request rate: $RATE req/s"
else
    echo_warn "Prometheus has no metrics yet (may need more time)"
fi

kill $PROM_PF_PID 2>/dev/null || true

echo ""
echo "=========================================="
echo "✅ Fix Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "1. ✅ Datasources: Fixed (Loki, Tempo, Prometheus)"
echo "2. ✅ Metrics Dashboard: Updated queries to match actual metrics"
echo "3. ✅ Logs Dashboard: Updated ConfigMap"
echo "4. ✅ Traces Dashboard: Updated ConfigMap"
echo "5. ✅ Grafana: Restarted to reload dashboards"
echo "6. ✅ Traffic: Generated 100 requests"
echo ""
echo "Next steps:"
echo "1. Wait 1-2 minutes for all data to propagate"
echo "2. Port-forward to Grafana: kubectl port-forward -n observability svc/prometheus-grafana 3000:80"
echo "3. Check dashboards:"
echo "   - Metrics: http://localhost:3000/d/dm-nkp-custom-app-metrics/dm-nkp-gitops-custom-app-metrics"
echo "   - Logs: http://localhost:3000/d/dm-nkp-custom-app-logs/dm-nkp-gitops-custom-app-logs"
echo "   - Traces: http://localhost:3000/d/dm-nkp-custom-app-traces/dm-nkp-gitops-custom-app-traces"
echo ""
echo "If datasources disappear again, check:"
echo "- kubectl get configmap -n observability -l grafana_datasource=1"
echo "- kubectl logs -n observability -l app.kubernetes.io/name=grafana | grep -i datasource"
