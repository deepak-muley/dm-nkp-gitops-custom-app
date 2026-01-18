#!/bin/bash
# Script to fix logs dashboard by updating queries to match actual labels in Loki

set -e

OBSERVABILITY_NAMESPACE="${OBSERVABILITY_NAMESPACE:-observability}"
DASHBOARD_CM_NAME="dm-nkp-gitops-custom-app-grafana-dashboard-logs"
DASHBOARD_FILE="chart/dm-nkp-gitops-custom-app/files/grafana/dashboard-logs.json"

echo "=========================================="
echo "Fixing Logs Dashboard Queries"
echo "=========================================="
echo ""

# Step 1: Check what labels are actually in Loki
echo "Step 1: Checking available labels in Loki..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/loki-loki-distributed-gateway 3100:80 >/dev/null 2>&1 &
LOKI_PF_PID=$!
sleep 3

START_TIME=$(date -u -v-1H +%s)000000000
END_TIME=$(date -u +%s)000000000

# Check for logs with any labels
LOKI_LABELS=$(curl -s "http://localhost:3100/loki/api/v1/labels" 2>/dev/null | jq -r '.data[]' 2>/dev/null || echo "")
LOKI_SAMPLE=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode "query={}" \
  --data-urlencode "start=${START_TIME}" \
  --data-urlencode "end=${END_TIME}" \
  --data-urlencode "limit=1" 2>/dev/null | jq -r '.data.result[0].stream | to_entries | map("\(.key)=\(.value)") | join(", ")' 2>/dev/null || echo "")

kill $LOKI_PF_PID 2>/dev/null || true

echo "Available labels in Loki: $LOKI_LABELS"
echo "Sample log stream labels: $LOKI_SAMPLE"
echo ""

# Step 2: Check if logs are being sent via OTLP or collected from stdout/stderr
echo "Step 2: Checking log collection method..."
OTEL_COLLECTOR_CONFIG=$(kubectl get opentelemetrycollector -n $OBSERVABILITY_NAMESPACE otel-collector -o yaml 2>/dev/null | grep -A 5 "logs:" | head -10 || echo "")
if echo "$OTEL_COLLECTOR_CONFIG" | grep -q "otlp"; then
    echo "✅ OTel Collector is configured to receive OTLP logs"
    echo "   Logs sent via OTLP will have 'service_name' or 'service.name' labels"
    echo "   Dashboard queries should use: {service_name=\"dm-nkp-gitops-custom-app\"} or {service.name=\"dm-nkp-gitops-custom-app\"}"
    QUERY_LABEL="service_name"
elif echo "$OTEL_COLLECTOR_CONFIG" | grep -q "filelog"; then
    echo "✅ OTel Collector is configured to collect stdout/stderr logs"
    echo "   Logs collected from pods will have 'app_kubernetes_io_name' labels"
    echo "   Dashboard queries should use: {app_kubernetes_io_name=\"dm-nkp-gitops-custom-app\"}"
    QUERY_LABEL="app_kubernetes_io_name"
else
    echo "⚠️  Could not determine log collection method"
    echo "   Trying both label patterns..."
    QUERY_LABEL="both"
fi
echo ""

# Step 3: Update dashboard queries
echo "Step 3: Updating dashboard queries..."

if [ -f "$DASHBOARD_FILE" ]; then
    # Backup original file
    cp "$DASHBOARD_FILE" "${DASHBOARD_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    echo "✅ Backed up original dashboard file"

    # Update queries based on what labels are actually available
    if [ "$QUERY_LABEL" = "service_name" ] || [ "$QUERY_LABEL" = "both" ]; then
        echo "Updating queries to use service_name label (OTLP logs)..."
        # Update queries to use service_name instead of app_kubernetes_io_name
        if command -v jq >/dev/null 2>&1; then
            jq '
              .panels[].targets[]? |= (
                if .expr then
                  .expr |= gsub("app_kubernetes_io_name"; "service_name")
                else
                  .
                end
              )
            ' "$DASHBOARD_FILE" > "${DASHBOARD_FILE}.tmp" && mv "${DASHBOARD_FILE}.tmp" "$DASHBOARD_FILE"
            echo "✅ Updated dashboard queries to use service_name label"
        else
            echo "⚠️  jq not found, using sed to update queries..."
            sed -i.bak 's/app_kubernetes_io_name/service_name/g' "$DASHBOARD_FILE"
            echo "✅ Updated dashboard queries using sed"
        fi
    fi

    # Step 4: Update ConfigMap in cluster
    echo ""
    echo "Step 4: Updating ConfigMap in cluster..."
    if kubectl get configmap "$DASHBOARD_CM_NAME" -n "$OBSERVABILITY_NAMESPACE" >/dev/null 2>&1; then
        kubectl create configmap "$DASHBOARD_CM_NAME" -n "$OBSERVABILITY_NAMESPACE" \
            --from-file=dm-nkp-gitops-custom-app-logs.json="$DASHBOARD_FILE" \
            --dry-run=client -o yaml | kubectl apply -f -

        # Ensure label is present
        if ! kubectl get configmap "$DASHBOARD_CM_NAME" -n "$OBSERVABILITY_NAMESPACE" -o jsonpath='{.metadata.labels.grafana_dashboard}' | grep -q "1"; then
            kubectl label configmap "$DASHBOARD_CM_NAME" -n "$OBSERVABILITY_NAMESPACE" grafana_dashboard="1" --overwrite
        fi

        echo "✅ ConfigMap updated"

        # Restart Grafana to reload dashboards
        echo ""
        echo "Step 5: Restarting Grafana to reload dashboards..."
        kubectl rollout restart deployment/prometheus-grafana -n "$OBSERVABILITY_NAMESPACE" 2>/dev/null || \
        kubectl rollout restart deployment/grafana -n "$OBSERVABILITY_NAMESPACE" 2>/dev/null || \
        echo "⚠️  Could not restart Grafana (may need manual restart)"

        echo "✅ Dashboard updated and Grafana restarted"
    else
        echo "⚠️  ConfigMap '$DASHBOARD_CM_NAME' not found in namespace '$OBSERVABILITY_NAMESPACE'"
        echo "   Dashboard will be updated on next Helm deployment"
    fi
else
    echo "❌ Dashboard file '$DASHBOARD_FILE' not found"
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ LOGS DASHBOARD FIXED"
echo "=========================================="
echo ""
echo "Changes made:"
echo "  ✅ Updated queries to use: {service_name=\"dm-nkp-gitops-custom-app\"}"
echo "  ✅ Updated ConfigMap in cluster"
echo "  ✅ Restarted Grafana"
echo ""
echo "Next steps:"
echo "1. Wait 30-60 seconds for Grafana to restart"
echo "2. Generate load: ./scripts/generate-load.sh"
echo "3. Check dashboard: Dashboards → dm-nkp-gitops-custom-app - Logs"
echo ""
echo "If logs still don't show:"
echo "  - Verify logs are being sent via OTLP (check app logs)"
echo "  - Verify OTEL_LOGS_ENABLED=true in deployment"
echo "  - Check OTel Collector logs for errors"
