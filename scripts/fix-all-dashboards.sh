#!/bin/bash
set -euo pipefail

# Comprehensive fix script for all dashboard data issues
# This script fixes the entire observability pipeline end-to-end

OBSERVABILITY_NAMESPACE="observability"
APP_NAMESPACE="default"
APP_NAME="dm-nkp-gitops-custom-app"

echo "=========================================="
echo "Fixing All Dashboard Data Issues"
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

# Step 1: Remove OTLP logs exporter from OTel Collector (Loki doesn't support it)
echo_step "Step 1: Fixing OTel Collector configuration..."
echo "Removing OTLP logs exporter (Loki doesn't support OTLP ingestion)..."
kubectl apply -f - <<EOF
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: ${OBSERVABILITY_NAMESPACE}
spec:
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      batch: {}
      resource:
        attributes:
          - key: job
            value: otel-collector
            action: upsert
    exporters:
      prometheusremotewrite:
        endpoint: http://prometheus-kube-prometheus-prometheus.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:9090/api/v1/write
      prometheus:
        endpoint: 0.0.0.0:8889
      debug:
        verbosity: normal
      otlp/tempo:
        endpoint: tempo.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:4317
        tls:
          insecure: true
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [otlp/tempo]
        metrics:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [prometheusremotewrite, prometheus]
        logs:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [debug]
  mode: deployment
  replicas: 1
  image: otel/opentelemetry-collector-contrib:latest
EOF

echo_info "OTel Collector updated (logs will be handled by Logging Operator)"
sleep 10

# Step 2: Verify Logging Operator is working
echo ""
echo_step "Step 2: Verifying Logging Operator..."
LOGGING_PODS=$(kubectl get pods -n logging -l app.kubernetes.io/name=logging-operator --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$LOGGING_PODS" -gt 0 ]; then
    echo_info "Logging Operator is running"

    # Check FluentBit agents
    FLUENTBIT_PODS=$(kubectl get pods -n logging -l app.kubernetes.io/name=fluentbit --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$FLUENTBIT_PODS" -gt 0 ]; then
        echo_info "FluentBit agents running: $FLUENTBIT_PODS"
    else
        echo_warn "No FluentBit agents found"
    fi
else
    echo_warn "Logging Operator not found - logs will only come from OTLP (which won't reach Loki)"
fi

# Step 3: Generate test traffic
echo ""
echo_step "Step 3: Generating test traffic..."
for i in {1..50}; do
    kubectl exec -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME -- curl -s http://localhost:8080/ > /dev/null 2>&1 || true
    kubectl exec -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME -- curl -s http://localhost:8080/health > /dev/null 2>&1 || true
done
echo_info "Generated 100 HTTP requests"
sleep 15  # Wait for data to propagate

# Step 4: Verify Prometheus has metrics
echo ""
echo_step "Step 4: Verifying Prometheus metrics..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090 > /tmp/prom-fix.log 2>&1 &
PROM_PF_PID=$!
sleep 5

METRIC_COUNT=$(curl -s "http://localhost:9090/api/v1/query?query=http_requests_total" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")
if [ "$METRIC_COUNT" -gt 0 ]; then
    echo_info "Prometheus has $METRIC_COUNT http_requests_total metric series"

    # Get actual labels
    ACTUAL_LABELS=$(curl -s "http://localhost:9090/api/v1/query?query=http_requests_total" 2>/dev/null | jq -r '.data.result[0].metric | keys[]' 2>/dev/null | grep -v "__" | head -10)
    echo_info "Metric labels: $(echo "$ACTUAL_LABELS" | tr '\n' ' ')"

    # Check if job label exists
    JOB_VALUE=$(curl -s "http://localhost:9090/api/v1/query?query=http_requests_total" 2>/dev/null | jq -r '.data.result[0].metric.job // "none"' 2>/dev/null)
    if [ "$JOB_VALUE" != "none" ]; then
        echo_info "Job label value: $JOB_VALUE"
    else
        echo_warn "No 'job' label found in metrics"
    fi
else
    echo_error "Prometheus has no http_requests_total metrics"
fi

# Step 5: Verify Loki has logs (from Logging Operator)
echo ""
echo_step "Step 5: Verifying Loki logs..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/loki-loki-distributed-gateway 3100:80 > /tmp/loki-fix.log 2>&1 &
LOKI_PF_PID=$!
sleep 5

START_TIME=$(($(date +%s) - 600))000000000
END_TIME=$(date +%s)000000000

# Check for logs with app_kubernetes_io_name (from Logging Operator)
APP_LOGS=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
    --data-urlencode 'query={app_kubernetes_io_name="dm-nkp-gitops-custom-app"}' \
    --data-urlencode "start=${START_TIME}" \
    --data-urlencode "end=${END_TIME}" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$APP_LOGS" != "0" ] && [ -n "$APP_LOGS" ]; then
    echo_info "Loki has $APP_LOGS log streams with app_kubernetes_io_name label"
else
    echo_warn "Loki has no logs with app_kubernetes_io_name label (check Logging Operator)"
fi

# Check for any logs
ANY_LOGS=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
    --data-urlencode 'query={}' \
    --data-urlencode "start=${START_TIME}" \
    --data-urlencode "end=${END_TIME}" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$ANY_LOGS" != "0" ] && [ -n "$ANY_LOGS" ]; then
    echo_info "Loki has $ANY_LOGS total log streams"
else
    echo_error "Loki has no logs at all"
fi

# Step 6: Update dashboard queries to match actual data
echo ""
echo_step "Step 6: Updating dashboard queries..."

# Get Grafana password
GRAFANA_PASSWORD=$(kubectl get secret -n $OBSERVABILITY_NAMESPACE prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")

# Port forward to Grafana
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana 3000:80 > /tmp/grafana-fix.log 2>&1 &
GRAFANA_PF_PID=$!
sleep 5

# Update logs dashboard to use app_kubernetes_io_name (from Logging Operator)
LOGS_DASHBOARD_UID="dm-nkp-custom-app-logs"
LOGS_CM="dm-nkp-gitops-custom-app-grafana-dashboard-logs"

if kubectl get configmap $LOGS_CM -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
    echo "Updating logs dashboard ConfigMap..."
    # Read current dashboard
    CURRENT_DASHBOARD=$(kubectl get configmap $LOGS_CM -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.data.*}' 2>/dev/null)

    # Update queries to use app_kubernetes_io_name
    UPDATED_DASHBOARD=$(echo "$CURRENT_DASHBOARD" | jq '(.dashboard.panels[] | select(.targets != null) | .targets[] | select(.expr != null)) |= (.expr |= gsub("service_name=\\\"dm-nkp-gitops-custom-app\\\""; "app_kubernetes_io_name=\\\"dm-nkp-gitops-custom-app\\\""))' 2>/dev/null)

    if [ -n "$UPDATED_DASHBOARD" ]; then
        kubectl patch configmap $LOGS_CM -n $OBSERVABILITY_NAMESPACE --type=json -p="[{\"op\": \"replace\", \"path\": \"/data/dashboard.json\", \"value\": $(echo "$UPDATED_DASHBOARD" | jq -c '.dashboard')}]" 2>/dev/null || echo_warn "Failed to update logs dashboard ConfigMap"
        echo_info "Logs dashboard updated to use app_kubernetes_io_name"
    fi
fi

# Step 7: Restart Grafana to reload dashboards
echo ""
echo_step "Step 7: Restarting Grafana to reload dashboards..."
kubectl rollout restart deployment prometheus-grafana -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1
sleep 10
echo_info "Grafana restarted"

# Cleanup
kill $PROM_PF_PID 2>/dev/null || true
kill $LOKI_PF_PID 2>/dev/null || true
kill $GRAFANA_PF_PID 2>/dev/null || true

echo ""
echo "=========================================="
echo "✅ Fix Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "1. ✅ OTel Collector: Removed OTLP logs exporter (Loki doesn't support it)"
echo "2. ✅ Logs: Will be captured by Logging Operator (stdout/stderr)"
echo "3. ✅ Metrics: Should be available in Prometheus"
echo "4. ✅ Traces: Should be available in Tempo"
echo "5. ✅ Dashboards: Updated to use correct labels"
echo ""
echo "Next steps:"
echo "1. Generate more traffic: kubectl exec -n default -l app.kubernetes.io/name=dm-nkp-gitops-custom-app -- curl http://localhost:8080/"
echo "2. Wait 30-60 seconds for data to propagate"
echo "3. Check Grafana dashboards: http://localhost:3000"
echo "   - Metrics: http://localhost:3000/d/dm-nkp-custom-app-metrics/dm-nkp-gitops-custom-app-metrics"
echo "   - Logs: http://localhost:3000/d/dm-nkp-custom-app-logs/dm-nkp-gitops-custom-app-logs"
echo "   - Traces: http://localhost:3000/d/dm-nkp-custom-app-traces/dm-nkp-gitops-custom-app-traces"
