#!/bin/bash
set -euo pipefail

# Comprehensive end-to-end data flow verification script
# This script verifies the entire observability pipeline from app to dashboards

OBSERVABILITY_NAMESPACE="observability"
APP_NAMESPACE="default"
APP_NAME="dm-nkp-gitops-custom-app"

echo "=========================================="
echo "End-to-End Data Flow Verification"
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

ERRORS=0
WARNINGS=0

# Step 1: Verify application is running and configured
echo_step "Step 1: Verifying application configuration..."
APP_PODS=$(kubectl get pods -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$APP_PODS" -gt 0 ]; then
    echo_info "Application pods found: $APP_PODS"
    APP_POD=$(kubectl get pods -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    # Check OTLP endpoint configuration
    OTLP_ENDPOINT=$(kubectl exec -n $APP_NAMESPACE $APP_POD -- env 2>/dev/null | grep "OTEL_EXPORTER_OTLP_ENDPOINT" | cut -d= -f2 || echo "")
    if [ -n "$OTLP_ENDPOINT" ]; then
        echo_info "OTLP Endpoint configured: $OTLP_ENDPOINT"
    else
        echo_error "OTLP Endpoint not configured in application"
        ERRORS=$((ERRORS + 1))
    fi

    OTEL_LOGS_ENABLED=$(kubectl exec -n $APP_NAMESPACE $APP_POD -- env 2>/dev/null | grep "OTEL_LOGS_ENABLED" | cut -d= -f2 || echo "")
    if [ "$OTEL_LOGS_ENABLED" = "true" ]; then
        echo_info "OTLP Logs enabled: $OTEL_LOGS_ENABLED"
    else
        echo_warn "OTLP Logs not enabled (OTEL_LOGS_ENABLED=$OTEL_LOGS_ENABLED)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo_error "No application pods found"
    ERRORS=$((ERRORS + 1))
fi

# Step 2: Verify OTel Collector is running and configured
echo ""
echo_step "Step 2: Verifying OTel Collector..."
OTEL_PODS=$(kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$OTEL_PODS" -gt 0 ]; then
    echo_info "OTel Collector pods found: $OTEL_PODS"
    OTEL_POD=$(kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    # Check OTel Collector config
    if kubectl get opentelemetrycollector otel-collector -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
        echo_info "OTel Collector CR exists"

        # Check for prometheus exporter
        if kubectl get opentelemetrycollector otel-collector -n $OBSERVABILITY_NAMESPACE -o yaml 2>&1 | grep -q "prometheus:"; then
            echo_info "Prometheus exporter configured"
        else
            echo_error "Prometheus exporter not found in OTel Collector config"
            ERRORS=$((ERRORS + 1))
        fi

        # Check for Loki exporter
        LOKI_ENDPOINT=$(kubectl get opentelemetrycollector otel-collector -n $OBSERVABILITY_NAMESPACE -o yaml 2>&1 | grep -A 2 "otlphttp/loki:" | grep "endpoint:" | awk '{print $2}' || echo "")
        if [ -n "$LOKI_ENDPOINT" ]; then
            echo_info "Loki exporter configured: $LOKI_ENDPOINT"
            if echo "$LOKI_ENDPOINT" | grep -q "/loki/api/v1/push"; then
                echo_info "Loki endpoint format is correct"
            else
                echo_error "Loki endpoint format is incorrect (should be /loki/api/v1/push)"
                ERRORS=$((ERRORS + 1))
            fi
        else
            echo_error "Loki exporter not found in OTel Collector config"
            ERRORS=$((ERRORS + 1))
        fi

        # Check for Tempo exporter
        if kubectl get opentelemetrycollector otel-collector -n $OBSERVABILITY_NAMESPACE -o yaml 2>&1 | grep -q "otlp/tempo:"; then
            echo_info "Tempo exporter configured"
        else
            echo_error "Tempo exporter not found in OTel Collector config"
            ERRORS=$((ERRORS + 1))
        fi
    else
        echo_error "OTel Collector CR not found"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo_error "No OTel Collector pods found"
    ERRORS=$((ERRORS + 1))
fi

# Step 3: Generate test traffic
echo ""
echo_step "Step 3: Generating test traffic..."
for i in {1..50}; do
    kubectl exec -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME -- curl -s http://localhost:8080/ > /dev/null 2>&1 || true
    kubectl exec -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME -- curl -s http://localhost:8080/health > /dev/null 2>&1 || true
done
echo_info "Generated 100 HTTP requests"
sleep 10  # Wait for data to propagate

# Step 4: Check OTel Collector metrics endpoint
echo ""
echo_step "Step 4: Checking OTel Collector metrics endpoint..."
if [ -n "$OTEL_POD" ]; then
    METRICS_COUNT=$(kubectl exec -n $OBSERVABILITY_NAMESPACE $OTEL_POD -- curl -s http://localhost:8889/metrics 2>/dev/null | grep -c "^http_requests" || echo "0")
    if [ "$METRICS_COUNT" -gt 0 ]; then
        echo_info "OTel Collector has $METRICS_COUNT http_requests metrics"
        kubectl exec -n $OBSERVABILITY_NAMESPACE $OTEL_POD -- curl -s http://localhost:8889/metrics 2>/dev/null | grep "^http_requests" | head -3
    else
        echo_error "OTel Collector metrics endpoint has no http_requests metrics"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Step 5: Check Prometheus for metrics
echo ""
echo_step "Step 5: Checking Prometheus for metrics..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090 > /tmp/prom-verify.log 2>&1 &
PROM_PF_PID=$!
sleep 5

# Check if otel-collector target is up
TARGET_STATUS=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null | jq -r '.data.activeTargets[] | select(.labels.job == "otel-collector") | .health' 2>/dev/null || echo "unknown")
if [ "$TARGET_STATUS" = "up" ]; then
    echo_info "OTel Collector target is UP in Prometheus"
else
    echo_error "OTel Collector target is not UP in Prometheus (status: $TARGET_STATUS)"
    ERRORS=$((ERRORS + 1))
fi

# Check for http_requests_total metric
HTTP_REQUESTS_COUNT=$(curl -s "http://localhost:9090/api/v1/query?query=http_requests_total" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")
if [ "$HTTP_REQUESTS_COUNT" -gt 0 ]; then
    echo_info "Prometheus has $HTTP_REQUESTS_COUNT http_requests_total metric series"
    curl -s "http://localhost:9090/api/v1/query?query=http_requests_total" 2>/dev/null | jq -r '.data.result[0].metric | to_entries | map("\(.key)=\"\(.value)\"") | join(", ")' 2>/dev/null | head -1
else
    echo_error "Prometheus has no http_requests_total metrics"
    ERRORS=$((ERRORS + 1))
fi

# Check for rate query
RATE_VALUE=$(curl -s "http://localhost:9090/api/v1/query?query=sum(rate(http_requests_total{job=\"otel-collector\"}[5m]))" 2>/dev/null | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null)
if [ "$RATE_VALUE" != "0" ] && [ -n "$RATE_VALUE" ]; then
    echo_info "Prometheus rate query returns: $RATE_VALUE"
else
    echo_warn "Prometheus rate query returns no data (value: $RATE_VALUE)"
    WARNINGS=$((WARNINGS + 1))
fi

# Step 6: Check Loki for logs
echo ""
echo_step "Step 6: Checking Loki for logs..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/loki-loki-distributed-gateway 3100:80 > /tmp/loki-verify.log 2>&1 &
LOKI_PF_PID=$!
sleep 5

# Get available labels
LOKI_LABELS=$(curl -s "http://localhost:3100/loki/api/v1/labels" 2>/dev/null | jq -r '.data[]' 2>/dev/null | head -10)
if [ -n "$LOKI_LABELS" ]; then
    echo_info "Loki has labels: $(echo "$LOKI_LABELS" | tr '\n' ' ')"
else
    echo_warn "Loki has no labels (may have no logs yet)"
    WARNINGS=$((WARNINGS + 1))
fi

# Check for logs with service_name
START_TIME=$(($(date +%s) - 900))000000000
END_TIME=$(date +%s)000000000
SERVICE_NAME_LOGS=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
    --data-urlencode 'query={service_name="dm-nkp-gitops-custom-app"}' \
    --data-urlencode "start=${START_TIME}" \
    --data-urlencode "end=${END_TIME}" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$SERVICE_NAME_LOGS" != "0" ] && [ -n "$SERVICE_NAME_LOGS" ]; then
    echo_info "Loki has $SERVICE_NAME_LOGS log streams with service_name label"
else
    echo_warn "Loki has no logs with service_name label"
    WARNINGS=$((WARNINGS + 1))
fi

# Check for logs with app_kubernetes_io_name
APP_NAME_LOGS=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
    --data-urlencode 'query={app_kubernetes_io_name="dm-nkp-gitops-custom-app"}' \
    --data-urlencode "start=${START_TIME}" \
    --data-urlencode "end=${END_TIME}" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$APP_NAME_LOGS" != "0" ] && [ -n "$APP_NAME_LOGS" ]; then
    echo_info "Loki has $APP_NAME_LOGS log streams with app_kubernetes_io_name label"
else
    echo_warn "Loki has no logs with app_kubernetes_io_name label"
    WARNINGS=$((WARNINGS + 1))
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
    ERRORS=$((ERRORS + 1))
fi

# Step 7: Check Tempo for traces
echo ""
echo_step "Step 7: Checking Tempo for traces..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/tempo 3200:3200 > /tmp/tempo-verify.log 2>&1 &
TEMPO_PF_PID=$!
sleep 5

# Check Tempo API
TEMPO_HEALTH=$(curl -s "http://localhost:3200/ready" 2>/dev/null || echo "error")
if [ "$TEMPO_HEALTH" = "ready" ]; then
    echo_info "Tempo is ready"
else
    echo_warn "Tempo health check failed"
    WARNINGS=$((WARNINGS + 1))
fi

# Step 8: Check Grafana datasources
echo ""
echo_step "Step 8: Checking Grafana datasources..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana 3000:80 > /tmp/grafana-verify.log 2>&1 &
GRAFANA_PF_PID=$!
sleep 5

GRAFANA_PASSWORD=$(kubectl get secret -n $OBSERVABILITY_NAMESPACE prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")

for DS in "Prometheus" "Loki" "Tempo"; do
    DS_CHECK=$(curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:3000/api/datasources/name/${DS}" 2>/dev/null)
    if echo "$DS_CHECK" | jq -e '.id' >/dev/null 2>&1; then
        DS_URL=$(echo "$DS_CHECK" | jq -r '.url' 2>/dev/null)
        echo_info "$DS datasource configured: $DS_URL"
    else
        echo_error "$DS datasource not found"
        ERRORS=$((ERRORS + 1))
    fi
done

# Step 9: Check dashboard queries
echo ""
echo_step "Step 9: Analyzing dashboard queries vs actual data..."

# Get actual metric labels
ACTUAL_METRIC_LABELS=$(curl -s "http://localhost:9090/api/v1/query?query=http_requests_total" 2>/dev/null | jq -r '.data.result[0].metric | keys[]' 2>/dev/null | grep -v "__" | head -10)
echo_info "Actual metric labels: $(echo "$ACTUAL_METRIC_LABELS" | tr '\n' ' ')"

# Check if job label exists
if echo "$ACTUAL_METRIC_LABELS" | grep -q "job"; then
    JOB_VALUE=$(curl -s "http://localhost:9090/api/v1/query?query=http_requests_total" 2>/dev/null | jq -r '.data.result[0].metric.job // "none"' 2>/dev/null)
    echo_info "Metric job label value: $JOB_VALUE"
else
    echo_warn "Metric has no 'job' label"
    WARNINGS=$((WARNINGS + 1))
fi

# Cleanup
kill $PROM_PF_PID 2>/dev/null || true
kill $LOKI_PF_PID 2>/dev/null || true
kill $TEMPO_PF_PID 2>/dev/null || true
kill $GRAFANA_PF_PID 2>/dev/null || true

# Summary
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo_info "✅ All critical checks passed!"
else
    echo_error "❌ Found $ERRORS critical issues that need to be fixed"
fi

if [ $WARNINGS -gt 0 ]; then
    echo_warn "⚠️  Found $WARNINGS warnings (may need attention)"
fi
