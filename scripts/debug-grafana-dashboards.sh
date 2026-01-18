#!/bin/bash
set -euo pipefail

# Debug script to check why Grafana dashboards show no data

OBSERVABILITY_NAMESPACE="observability"
APP_NAMESPACE="default"
APP_NAME="dm-nkp-gitops-custom-app"

echo "=========================================="
echo "Grafana Dashboard Data Debug Script"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# Check if pods are running
echo "1. Checking pod status..."
echo "   Application pods:"
if kubectl get pods -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME 2>/dev/null | grep -q Running; then
    echo_info "Application pods are running"
    kubectl get pods -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME 2>/dev/null | grep Running
else
    echo_error "Application pods are not running"
fi

echo ""
echo "   OTel Collector pods:"
if kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep -q Running; then
    echo_info "OTel Collector pods are running"
    kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep Running
else
    echo_error "OTel Collector pods are not running"
fi

echo ""
echo "   Prometheus pods:"
if kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=prometheus 2>/dev/null | grep -q Running; then
    echo_info "Prometheus pods are running"
    kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=prometheus 2>/dev/null | grep Running | head -1
else
    echo_error "Prometheus pods are not running"
fi

echo ""
echo "   Grafana pods:"
if kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=grafana 2>/dev/null | grep -q Running; then
    echo_info "Grafana pods are running"
    kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=grafana 2>/dev/null | grep Running | head -1
else
    echo_error "Grafana pods are not running"
fi

# Check ServiceMonitor
echo ""
echo "2. Checking ServiceMonitor for OTel Collector..."
if kubectl get servicemonitor -n $OBSERVABILITY_NAMESPACE otel-collector 2>/dev/null | grep -q otel-collector; then
    echo_info "ServiceMonitor exists"
    kubectl get servicemonitor -n $OBSERVABILITY_NAMESPACE otel-collector -o yaml 2>/dev/null | grep -A 5 "port:" || true
else
    echo_error "ServiceMonitor not found"
fi

# Check OTel Collector service
echo ""
echo "3. Checking OTel Collector service..."
if kubectl get svc -n $OBSERVABILITY_NAMESPACE otel-collector-collector 2>/dev/null | grep -q otel-collector; then
    echo_info "OTel Collector service exists"
    kubectl get svc -n $OBSERVABILITY_NAMESPACE otel-collector-collector -o yaml 2>/dev/null | grep -A 3 "ports:" || true
else
    echo_error "OTel Collector service not found"
fi

# Port forward and check Prometheus
echo ""
echo "4. Checking Prometheus for metrics..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090 > /tmp/prometheus-pf-$$.log 2>&1 &
PROMETHEUS_PF_PID=$!
sleep 3

# Check if otel-collector target is up
TARGET_STATUS=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null | jq -r '.data.activeTargets[] | select(.labels.job == "otel-collector") | .health' 2>/dev/null || echo "unknown")
if [ "$TARGET_STATUS" = "up" ]; then
    echo_info "OTel Collector target is UP in Prometheus"
elif [ "$TARGET_STATUS" = "down" ]; then
    echo_error "OTel Collector target is DOWN in Prometheus"
    curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null | jq -r '.data.activeTargets[] | select(.labels.job == "otel-collector") | .lastError' 2>/dev/null || true
else
    echo_warn "OTel Collector target not found in Prometheus"
fi

# Check for metrics
echo ""
echo "   Checking for http_requests_total metric..."
HTTP_REQUESTS=$(curl -s "http://localhost:9090/api/v1/query?query=sum(rate(http_requests_total{job=\"otel-collector\"}[5m]))" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")
if [ "$HTTP_REQUESTS" != "0" ] && [ "$HTTP_REQUESTS" != "" ]; then
    echo_info "Found http_requests_total metric"
    curl -s "http://localhost:9090/api/v1/query?query=sum(rate(http_requests_total{job=\"otel-collector\"}[5m]))" 2>/dev/null | jq -r '.data.result[] | "Value: \(.value[1])"' 2>/dev/null || true
else
    echo_warn "No http_requests_total metric found"
    echo "   Checking available metrics with 'http' in name..."
    curl -s "http://localhost:9090/api/v1/label/__name__/values" 2>/dev/null | jq -r '.data[]' | grep -i http | head -5 || echo "   No HTTP metrics found"
fi

# Check OTel Collector metrics endpoint
echo ""
echo "5. Checking OTel Collector metrics endpoint (port 8889)..."
OTEL_COLLECTOR_POD=$(kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$OTEL_COLLECTOR_POD" ]; then
    METRICS_CHECK=$(kubectl exec -n $OBSERVABILITY_NAMESPACE $OTEL_COLLECTOR_POD -- curl -s http://localhost:8889/metrics 2>/dev/null | grep -c "http_requests" || echo "0")
    if [ "$METRICS_CHECK" != "0" ]; then
        echo_info "OTel Collector metrics endpoint has http_requests metrics"
        kubectl exec -n $OBSERVABILITY_NAMESPACE $OTEL_COLLECTOR_POD -- curl -s http://localhost:8889/metrics 2>/dev/null | grep "http_requests" | head -3
    else
        echo_warn "OTel Collector metrics endpoint does not have http_requests metrics"
        echo "   Checking what metrics are available..."
        kubectl exec -n $OBSERVABILITY_NAMESPACE $OTEL_COLLECTOR_POD -- curl -s http://localhost:8889/metrics 2>/dev/null | grep -E "^[a-z]" | head -10 || true
    fi
else
    echo_error "OTel Collector pod not found"
fi

# Check Grafana datasources
echo ""
echo "6. Checking Grafana datasources..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana 3000:80 > /tmp/grafana-pf-$$.log 2>&1 &
GRAFANA_PF_PID=$!
sleep 3

GRAFANA_PASSWORD=$(kubectl get secret -n $OBSERVABILITY_NAMESPACE prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")

for DS in "Prometheus" "Loki" "Tempo"; do
    DS_CHECK=$(curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:3000/api/datasources/name/${DS}" 2>/dev/null)
    if echo "$DS_CHECK" | grep -q '"id"'; then
        DS_URL=$(echo "$DS_CHECK" | jq -r '.url' 2>/dev/null || echo "unknown")
        echo_info "$DS datasource configured: $DS_URL"
    else
        echo_error "$DS datasource not found"
    fi
done

# Check dashboards
echo ""
echo "7. Checking Grafana dashboards..."
DASHBOARDS=$(curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:3000/api/search?query=dm-nkp" 2>/dev/null | jq -r '.[] | .title' 2>/dev/null || echo "")
if [ -n "$DASHBOARDS" ]; then
    echo_info "Found dashboards:"
    echo "$DASHBOARDS" | while read -r dash; do
        echo "   - $dash"
    done
else
    echo_warn "No dashboards found matching 'dm-nkp'"
fi

# Check Loki for logs
echo ""
echo "8. Checking Loki for logs..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/loki-loki-distributed-gateway 3100:80 > /tmp/loki-pf-$$.log 2>&1 &
LOKI_PF_PID=$!
sleep 3

# Check for OTLP logs
OTLP_LOGS=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
    --data-urlencode 'query={service_name="dm-nkp-gitops-custom-app"}' \
    --data-urlencode "start=$(date -u -v-15M +%s)000000000" \
    --data-urlencode "end=$(date -u +%s)000000000" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$OTLP_LOGS" != "0" ] && [ "$OTLP_LOGS" != "" ]; then
    echo_info "Found OTLP logs in Loki (service_name label)"
else
    echo_warn "No OTLP logs found with service_name label"
fi

# Check for stdout/stderr logs
STDOUT_LOGS=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
    --data-urlencode 'query={app_kubernetes_io_name="dm-nkp-gitops-custom-app"}' \
    --data-urlencode "start=$(date -u -v-15M +%s)000000000" \
    --data-urlencode "end=$(date -u +%s)000000000" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$STDOUT_LOGS" != "0" ] && [ "$STDOUT_LOGS" != "" ]; then
    echo_info "Found stdout/stderr logs in Loki (app_kubernetes_io_name label)"
else
    echo_warn "No stdout/stderr logs found with app_kubernetes_io_name label"
fi

# Generate some traffic
echo ""
echo "9. Generating test traffic..."
for i in {1..10}; do
    kubectl exec -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME -- curl -s http://localhost:8080/ > /dev/null 2>&1 || true
done
echo_info "Generated 10 HTTP requests"
sleep 5

# Check again for metrics
echo ""
echo "10. Re-checking metrics after traffic..."
HTTP_REQUESTS_AFTER=$(curl -s "http://localhost:9090/api/v1/query?query=sum(rate(http_requests_total{job=\"otel-collector\"}[5m]))" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")
if [ "$HTTP_REQUESTS_AFTER" != "0" ] && [ "$HTTP_REQUESTS_AFTER" != "" ]; then
    echo_info "Metrics appeared after traffic generation"
    curl -s "http://localhost:9090/api/v1/query?query=sum(rate(http_requests_total{job=\"otel-collector\"}[5m]))" 2>/dev/null | jq -r '.data.result[] | "Value: \(.value[1])"' 2>/dev/null || true
else
    echo_error "Still no metrics after traffic generation"
fi

# Cleanup
echo ""
echo "Cleaning up port-forwards..."
kill $PROMETHEUS_PF_PID 2>/dev/null || true
kill $GRAFANA_PF_PID 2>/dev/null || true
kill $LOKI_PF_PID 2>/dev/null || true

echo ""
echo "=========================================="
echo "Debug complete!"
echo "=========================================="
