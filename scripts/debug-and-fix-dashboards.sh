#!/bin/bash
set -euo pipefail

# Comprehensive debug and fix script for dashboard data issues

OBSERVABILITY_NAMESPACE="observability"
APP_NAMESPACE="default"
APP_NAME="dm-nkp-gitops-custom-app"

echo "=========================================="
echo "Debugging and Fixing Dashboard Data Issues"
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

# Step 1: Generate significant traffic
echo_step "Step 1: Generating traffic..."
for i in {1..100}; do
    kubectl exec -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME -- curl -s http://localhost:8080/ > /dev/null 2>&1 || true
    kubectl exec -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME -- curl -s http://localhost:8080/health > /dev/null 2>&1 || true
done
echo_info "Generated 200 HTTP requests"
sleep 30  # Wait for metrics to be exported (OTel SDK uses 30s interval)

# Step 2: Check OTel Collector prometheus endpoint
echo ""
echo_step "Step 2: Checking OTel Collector prometheus endpoint..."
OTEL_POD=$(kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$OTEL_POD" ]; then
    METRICS_OUTPUT=$(kubectl exec -n $OBSERVABILITY_NAMESPACE $OTEL_POD -- curl -s http://localhost:8889/metrics 2>/dev/null || echo "")
    if [ -n "$METRICS_OUTPUT" ]; then
        HTTP_REQUESTS_COUNT=$(echo "$METRICS_OUTPUT" | grep -c "^http_requests" || echo "0")
        if [ "$HTTP_REQUESTS_COUNT" -gt 0 ]; then
            echo_info "OTel Collector prometheus endpoint has $HTTP_REQUESTS_COUNT http_requests metrics"
            echo "$METRICS_OUTPUT" | grep "^http_requests" | head -5
        else
            echo_error "OTel Collector prometheus endpoint has no http_requests metrics"
            echo "Available metrics:"
            echo "$METRICS_OUTPUT" | grep -v "^#" | grep -v "^$" | head -10
        fi
    else
        echo_error "OTel Collector prometheus endpoint not accessible"
    fi
else
    echo_error "OTel Collector pod not found"
fi

# Step 3: Check Prometheus
echo ""
echo_step "Step 3: Checking Prometheus..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090 > /tmp/prom-debug.log 2>&1 &
PROM_PF_PID=$!
sleep 5

# Check target
TARGET_STATUS=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null | jq -r '.data.activeTargets[] | select(.labels.job == "otel-collector") | .health' 2>/dev/null || echo "unknown")
echo_info "OTel Collector target status: $TARGET_STATUS"

# Check for metrics
METRIC_COUNT=$(curl -s "http://localhost:9090/api/v1/query?query=http_requests_total" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")
if [ "$METRIC_COUNT" -gt 0 ]; then
    echo_info "Prometheus has $METRIC_COUNT http_requests_total metric series"
    curl -s "http://localhost:9090/api/v1/query?query=http_requests_total" 2>/dev/null | jq -r '.data.result[0].metric | to_entries | map("\(.key)=\"\(.value)\"") | join(", ")' 2>/dev/null | head -1
else
    echo_error "Prometheus has no http_requests_total metrics"
    echo "Checking what metrics Prometheus has from otel-collector job..."
    curl -s "http://localhost:9090/api/v1/query?query={job=\"otel-collector\"}" 2>/dev/null | jq -r '.data.result[] | .metric.__name__' 2>/dev/null | head -10
fi

# Step 4: Check Loki
echo ""
echo_step "Step 4: Checking Loki..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/loki-loki-distributed-gateway 3100:80 > /tmp/loki-debug.log 2>&1 &
LOKI_PF_PID=$!
sleep 5

START_TIME=$(($(date +%s) - 600))000000000
END_TIME=$(date +%s)000000000

APP_LOGS=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
    --data-urlencode 'query={app_kubernetes_io_name="dm-nkp-gitops-custom-app"}' \
    --data-urlencode "start=${START_TIME}" \
    --data-urlencode "end=${END_TIME}" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$APP_LOGS" != "0" ] && [ -n "$APP_LOGS" ]; then
    echo_info "Loki has $APP_LOGS log streams"
else
    echo_warn "Loki has no logs with app_kubernetes_io_name label"
fi

# Step 5: Check Tempo
echo ""
echo_step "Step 5: Checking Tempo..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/tempo 3200:3200 > /tmp/tempo-debug.log 2>&1 &
TEMPO_PF_PID=$!
sleep 5

TEMPO_HEALTH=$(curl -s "http://localhost:3200/ready" 2>/dev/null || echo "error")
if [ "$TEMPO_HEALTH" = "ready" ]; then
    echo_info "Tempo is ready"
else
    echo_warn "Tempo health check failed"
fi

# Step 6: Summary and recommendations
echo ""
echo "=========================================="
echo "Summary and Recommendations"
echo "=========================================="

if [ "$METRIC_COUNT" -eq 0 ]; then
    echo_error "CRITICAL: No metrics in Prometheus"
    echo ""
    echo "Possible causes:"
    echo "1. Application not sending metrics to OTel Collector"
    echo "2. OTel Collector not receiving metrics"
    echo "3. OTel Collector prometheus exporter not working"
    echo "4. Prometheus not scraping OTel Collector"
    echo ""
    echo "Next steps:"
    echo "1. Check app logs: kubectl logs -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME | grep -i metric"
    echo "2. Check OTel Collector logs: kubectl logs -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator | grep -i metric"
    echo "3. Check OTel Collector prometheus endpoint: kubectl exec -n $OBSERVABILITY_NAMESPACE $OTEL_POD -- curl http://localhost:8889/metrics"
    echo "4. Check Prometheus targets: http://localhost:9090/targets"
fi

# Cleanup
kill $PROM_PF_PID 2>/dev/null || true
kill $LOKI_PF_PID 2>/dev/null || true
kill $TEMPO_PF_PID 2>/dev/null || true

echo ""
echo "Debugging complete!"
