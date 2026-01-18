#!/bin/bash
# Script to generate load for testing logs, traces, and metrics

set -e

APP_NAMESPACE="${APP_NAMESPACE:-default}"
APP_NAME="${APP_NAME:-dm-nkp-gitops-custom-app}"
APP_PORT="${APP_PORT:-8080}"
REQUESTS="${REQUESTS:-100}"
DELAY="${DELAY:-0.1}"
ENDPOINTS="${ENDPOINTS:-/ /health /ready}"

echo "=========================================="
echo "Load Generation Script"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Namespace: $APP_NAMESPACE"
echo "  Service: $APP_NAME"
echo "  Port: $APP_PORT"
echo "  Requests: $REQUESTS"
echo "  Delay: ${DELAY}s"
echo "  Endpoints: $ENDPOINTS"
echo ""

# Check if service exists
if ! kubectl get svc -n $APP_NAMESPACE $APP_NAME >/dev/null 2>&1; then
    echo "❌ Error: Service $APP_NAME not found in namespace $APP_NAMESPACE"
    exit 1
fi

# Port forward in background
echo "Step 1: Setting up port forward..."
kubectl port-forward -n $APP_NAMESPACE svc/$APP_NAME $APP_PORT:8080 >/dev/null 2>&1 &
PF_PID=$!
sleep 3

# Check if port forward is working
if ! curl -s http://localhost:$APP_PORT/health >/dev/null 2>&1; then
    echo "❌ Error: Cannot connect to application on port $APP_PORT"
    kill $PF_PID 2>/dev/null || true
    exit 1
fi

echo "✅ Port forward established"
echo ""

# Generate load
echo "Step 2: Generating load..."
echo "Sending $REQUESTS requests to each endpoint..."
echo ""

TOTAL_REQUESTS=0
SUCCESS_COUNT=0
ERROR_COUNT=0

for endpoint in $ENDPOINTS; do
    echo "  Generating load for: $endpoint"
    for i in $(seq 1 $REQUESTS); do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:$APP_PORT$endpoint >/dev/null 2>&1; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            ERROR_COUNT=$((ERROR_COUNT + 1))
        fi
        TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
        sleep $DELAY

        # Progress indicator
        if [ $((i % 10)) -eq 0 ]; then
            echo -n "."
        fi
    done
    echo ""
done

echo ""
echo "=========================================="
echo "Load Generation Complete"
echo "=========================================="
echo "Total Requests: $TOTAL_REQUESTS"
echo "Successful: $SUCCESS_COUNT"
echo "Errors: $ERROR_COUNT"
echo ""
echo "Waiting 10 seconds for telemetry to be collected..."
sleep 10

# Cleanup
kill $PF_PID 2>/dev/null || true

echo ""
echo "✅ Load generation complete!"
echo ""
echo "Next steps:"
echo "1. Check Grafana for logs and traces"
echo "2. Run: ./scripts/verify-logs-traces.sh"
echo "3. Or manually check Grafana Explore"
