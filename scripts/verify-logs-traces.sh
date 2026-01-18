#!/bin/bash
# Script to verify logs and traces are working with Grafana

set -e

OBSERVABILITY_NAMESPACE="${OBSERVABILITY_NAMESPACE:-observability}"
APP_NAMESPACE="${APP_NAMESPACE:-default}"
APP_NAME="${APP_NAME:-dm-nkp-gitops-custom-app}"

echo "=========================================="
echo "Verifying Logs and Traces in Grafana"
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

# Check datasources
echo ""
echo "Step 3: Checking Grafana datasources..."
DATASOURCES=$(curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:3000/api/datasources" 2>/dev/null)

LOKI_FOUND=false
TEMPO_FOUND=false

echo "$DATASOURCES" | jq -r '.[] | "  ✅ \(.name) (\(.type)): \(.url)"' 2>/dev/null || echo "$DATASOURCES"

if echo "$DATASOURCES" | jq -r '.[] | select(.type=="loki") | .name' 2>/dev/null | grep -q .; then
    LOKI_FOUND=true
    echo "✅ Loki datasource found"
else
    echo "❌ Loki datasource not found"
fi

if echo "$DATASOURCES" | jq -r '.[] | select(.type=="tempo") | .name' 2>/dev/null | grep -q .; then
    TEMPO_FOUND=true
    echo "✅ Tempo datasource found"
else
    echo "❌ Tempo datasource not found"
fi

# Generate traffic
echo ""
echo "Step 4: Generating traffic to create logs and traces..."
kubectl port-forward -n $APP_NAMESPACE svc/$APP_NAME 8080:8080 >/dev/null 2>&1 &
APP_PF_PID=$!
sleep 3

for i in {1..50}; do
    curl -s http://localhost:8080/ >/dev/null 2>&1 || true
    sleep 0.1
done

kill $APP_PF_PID 2>/dev/null || true
echo "✅ Generated 50 requests"

# Wait for telemetry to be collected
echo ""
echo "Step 5: Waiting for telemetry to be collected..."
sleep 10

# Test Loki query
echo ""
echo "Step 6: Testing Loki query..."
if [ "$LOKI_FOUND" = "true" ]; then
    LOKI_UID=$(echo "$DATASOURCES" | jq -r '.[] | select(.type=="loki") | .uid' 2>/dev/null | head -1)
    if [ -n "$LOKI_UID" ]; then
        START_TIME=$(date -u -v-5M +%s)000000000
        END_TIME=$(date -u +%s)000000000

        LOKI_RESULT=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
            -X POST "http://localhost:3000/api/datasources/proxy/uid/${LOKI_UID}/api/v1/query_range" \
            -H "Content-Type: application/json" \
            -d "{\"query\":\"{job=~\\\"dm-nkp.*|otel.*\\\"}\",\"start\":\"${START_TIME}\",\"end\":\"${END_TIME}\",\"limit\":10}" 2>/dev/null)

        LOG_COUNT=$(echo "$LOKI_RESULT" | jq -r '.data.result[]?.values | length' 2>/dev/null | awk '{sum+=$1} END {print sum+0}')

        if [ "$LOG_COUNT" -gt 0 ] 2>/dev/null; then
            echo "✅ Loki has logs: $LOG_COUNT log entries found"
        else
            echo "⚠️  Loki query returned no logs (may need more time or check OTel Collector)"
        fi
    else
        echo "⚠️  Could not find Loki datasource UID"
    fi
else
    echo "⚠️  Skipping Loki test (datasource not found)"
fi

# Test Tempo query
echo ""
echo "Step 7: Testing Tempo query..."
if [ "$TEMPO_FOUND" = "true" ]; then
    TEMPO_UID=$(echo "$DATASOURCES" | jq -r '.[] | select(.type=="tempo") | .uid' 2>/dev/null | head -1)
    if [ -n "$TEMPO_UID" ]; then
        TEMPO_RESULT=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
            -X GET "http://localhost:3000/api/datasources/proxy/uid/${TEMPO_UID}/api/search?limit=5" 2>/dev/null)

        TRACE_COUNT=$(echo "$TEMPO_RESULT" | jq -r '.traces | length' 2>/dev/null || echo "0")

        if [ "$TRACE_COUNT" -gt 0 ] 2>/dev/null; then
            echo "✅ Tempo has traces: $TRACE_COUNT traces found"
            echo "$TEMPO_RESULT" | jq -r '.traces[]?.traceID' 2>/dev/null | head -3 | while read trace_id; do
                echo "  - Trace ID: $trace_id"
            done
        else
            echo "⚠️  Tempo query returned no traces (may need more time or check OTel Collector)"
        fi
    else
        echo "⚠️  Could not find Tempo datasource UID"
    fi
else
    echo "⚠️  Skipping Tempo test (datasource not found)"
fi

# Check OTel Collector
echo ""
echo "Step 8: Checking OTel Collector status..."
OTEL_PODS=$(kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$OTEL_PODS" -gt 0 ]; then
    echo "✅ OTel Collector pods: $OTEL_PODS"
    kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector --no-headers 2>/dev/null | head -1 | awk '{print "  - Pod: " $1 " - Status: " $3}'
else
    echo "❌ OTel Collector pods not found"
fi

# Summary
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo "Grafana: http://localhost:3000 (admin/${GRAFANA_PASSWORD})"
echo ""
if [ "$LOKI_FOUND" = "true" ]; then
    echo "✅ Loki datasource: Configured"
else
    echo "❌ Loki datasource: Not configured"
fi
if [ "$TEMPO_FOUND" = "true" ]; then
    echo "✅ Tempo datasource: Configured"
else
    echo "❌ Tempo datasource: Not configured"
fi
echo ""
echo "Next steps:"
echo "1. Open Grafana: http://localhost:3000"
echo "2. Go to Explore → Select Loki → Query: {job=~\"dm-nkp.*|otel.*\"}"
echo "3. Go to Explore → Select Tempo → Search for traces"
echo "4. Check dashboards: dm-nkp-gitops-custom-app - Logs and Metrics"

# Cleanup
kill $GRAFANA_PF_PID 2>/dev/null || true
