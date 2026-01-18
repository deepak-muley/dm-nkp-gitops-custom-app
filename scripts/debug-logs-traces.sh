#!/bin/bash
# Script to debug why logs and traces are not showing in Grafana

set -e

OBSERVABILITY_NAMESPACE="${OBSERVABILITY_NAMESPACE:-observability}"
APP_NAMESPACE="${APP_NAMESPACE:-default}"
APP_NAME="${APP_NAME:-dm-nkp-gitops-custom-app}"

echo "=========================================="
echo "Debugging Logs and Traces"
echo "=========================================="
echo ""

# Step 1: Check OTel Collector status
echo "Step 1: Checking OTel Collector..."
OTEL_POD=$(kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector --no-headers 2>/dev/null | head -1 | awk '{print $1}')
if [ -z "$OTEL_POD" ]; then
    # Try alternative label
    OTEL_POD=$(kubectl get pods -n $OBSERVABILITY_NAMESPACE | grep -i collector | head -1 | awk '{print $1}')
fi
if [ -z "$OTEL_POD" ]; then
    echo "❌ OTel Collector pod not found"
    echo "Available pods in $OBSERVABILITY_NAMESPACE:"
    kubectl get pods -n $OBSERVABILITY_NAMESPACE | grep -i collector || echo "  No collector pods found"
    exit 1
fi
echo "✅ OTel Collector pod: $OTEL_POD"
echo ""

# Step 2: Check OTel Collector configuration
echo "Step 2: Checking OTel Collector configuration..."
kubectl get opentelemetrycollector -n $OBSERVABILITY_NAMESPACE otel-collector -o yaml 2>&1 | grep -A 10 "logs:" | head -15
echo ""

# Step 3: Check if logs pipeline is configured
echo "Step 3: Verifying logs pipeline..."
LOGS_PIPELINE=$(kubectl get opentelemetrycollector -n $OBSERVABILITY_NAMESPACE otel-collector -o yaml 2>&1 | grep -A 5 "logs:" | grep -c "otlphttp/loki" || echo "0")
if [ "$LOGS_PIPELINE" -gt 0 ]; then
    echo "✅ Logs pipeline configured with otlphttp/loki"
else
    echo "❌ Logs pipeline not configured correctly"
fi
echo ""

# Step 4: Check OTel Collector logs for errors
echo "Step 4: Checking OTel Collector logs for errors..."
kubectl logs -n $OBSERVABILITY_NAMESPACE $OTEL_POD --tail=100 2>&1 | grep -i "error\|warn\|log" | tail -20
echo ""

# Step 5: Check if application is sending logs
echo "Step 5: Checking application logs..."
APP_PODS=$(kubectl get pods -n $APP_NAMESPACE -l app=$APP_NAME --no-headers 2>/dev/null | head -2)
if [ -z "$APP_PODS" ]; then
    echo "⚠️  Application pods not found"
else
    echo "Application pods:"
    echo "$APP_PODS" | while read pod rest; do
        echo "  - $pod"
        echo "    Recent logs:"
        kubectl logs -n $APP_NAMESPACE $pod --tail=5 2>&1 | sed 's/^/      /'
    done
fi
echo ""

# Step 6: Check application environment variables
echo "Step 6: Checking application OTLP configuration..."
APP_POD=$(echo "$APP_PODS" | head -1 | awk '{print $1}')
if [ -n "$APP_POD" ]; then
    echo "Checking environment variables in $APP_POD:"
    kubectl exec -n $APP_NAMESPACE $APP_POD -- env 2>&1 | grep -i "OTEL" | sed 's/^/  /' || echo "  No OTEL environment variables found"
fi
echo ""

# Step 7: Check OTel Collector metrics
echo "Step 7: Checking OTel Collector metrics..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE $OTEL_POD 8888:8888 >/dev/null 2>&1 &
METRICS_PF_PID=$!
sleep 3

echo "Logs exporter metrics:"
kubectl exec -n $OBSERVABILITY_NAMESPACE $OTEL_POD -- wget -qO- http://localhost:8888/metrics 2>&1 | grep -i "otelcol_exporter.*log" | head -10 || echo "  No logs exporter metrics found"

kill $METRICS_PF_PID 2>/dev/null || true
echo ""

# Step 8: Check Loki directly
echo "Step 8: Checking Loki for logs..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/loki-loki-distributed-gateway 3100:80 >/dev/null 2>&1 &
LOKI_PF_PID=$!
sleep 3

echo "Loki labels:"
curl -s "http://localhost:3100/loki/api/v1/labels" 2>&1 | jq -r '.data[]' 2>/dev/null | head -10 || echo "  Could not query Loki"

echo ""
echo "Recent log query:"
START=$(date -u -v-10M +%s)000000000
END=$(date -u +%s)000000000
curl -s "http://localhost:3100/loki/api/v1/query_range?query={}&start=${START}&end=${END}&limit=5" 2>&1 | jq -r '.data.result[]?.values | length' 2>/dev/null | awk '{sum+=$1} END {print "  Log entries: " sum+0}' || echo "  No logs found"

kill $LOKI_PF_PID 2>/dev/null || true
echo ""

# Step 9: Check Tempo directly
echo "Step 9: Checking Tempo for traces..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/tempo 3200:3200 >/dev/null 2>&1 &
TEMPO_PF_PID=$!
sleep 3

echo "Recent traces:"
TRACES=$(curl -s "http://localhost:3200/api/search?limit=5" 2>&1)
TRACE_COUNT=$(echo "$TRACES" | jq -r '.traces | length' 2>/dev/null || echo "0")
echo "  Trace count: $TRACE_COUNT"
if [ "$TRACE_COUNT" -gt 0 ]; then
    echo "$TRACES" | jq -r '.traces[]?.traceID' 2>/dev/null | head -3 | while read trace_id; do
        echo "    - $trace_id"
    done
else
    echo "  No traces found"
fi

kill $TEMPO_PF_PID 2>/dev/null || true
echo ""

# Step 10: Summary and recommendations
echo "=========================================="
echo "Debug Summary"
echo "=========================================="
echo ""
echo "Common Issues and Solutions:"
echo ""
echo "1. If logs are not in Loki:"
echo "   - Check if application is sending logs via OTLP (not just stdout/stderr)"
echo "   - Verify OTEL_LOGS_ENABLED=true in application"
echo "   - Check OTel Collector logs for errors"
echo "   - Generate more traffic: ./scripts/generate-load.sh"
echo ""
echo "2. If traces are not in Tempo:"
echo "   - Verify application is sending traces via OTLP"
echo "   - Check OTEL_EXPORTER_OTLP_ENDPOINT is correct"
echo "   - Generate more traffic: ./scripts/generate-load.sh"
echo ""
echo "3. If OTel Collector has errors:"
echo "   - Check OTel Collector configuration"
echo "   - Verify Loki/Tempo endpoints are correct"
echo "   - Check network connectivity"
echo ""
echo "Next steps:"
echo "1. Generate load: ./scripts/generate-load.sh"
echo "2. Wait 30-60 seconds"
echo "3. Verify: ./scripts/verify-logs-traces.sh"
echo "4. Check Grafana: http://localhost:3000"
