#!/bin/bash
set -euo pipefail

# Script to fix missing Grafana datasources (Loki and Tempo)

OBSERVABILITY_NAMESPACE="observability"
LOCAL_PORT=3000

echo "=========================================="
echo "Fixing Grafana Datasources"
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

# Get Grafana password
GRAFANA_PASSWORD=$(kubectl get secret -n $OBSERVABILITY_NAMESPACE prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")

# Port forward to Grafana
echo "Starting Grafana port-forward..."
pkill -f "kubectl port-forward.*3000" 2>/dev/null || true
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana $LOCAL_PORT:80 > /tmp/grafana-pf-fix.log 2>&1 &
GRAFANA_PF_PID=$!
sleep 5

# Wait for Grafana API
echo "Waiting for Grafana API..."
API_READY=false
for i in {1..30}; do
    if curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:${LOCAL_PORT}/api/health" >/dev/null 2>&1; then
        API_READY=true
        break
    fi
    sleep 1
done

if [ "$API_READY" != "true" ]; then
    echo_error "Grafana API not ready after 30 seconds"
    kill $GRAFANA_PF_PID 2>/dev/null || true
    exit 1
fi

echo_info "Grafana API is ready"

# Find Loki service
echo ""
echo "Finding Loki service..."
LOKI_SVC=""
LOKI_PORT=""
if kubectl get svc loki-loki-distributed-gateway -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
    LOKI_SVC="loki-loki-distributed-gateway"
    LOKI_PORT=$(kubectl get svc "$LOKI_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null || echo "80")
    echo_info "Found Loki service: $LOKI_SVC (port: $LOKI_PORT)"
elif kubectl get svc loki -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
    LOKI_SVC="loki"
    LOKI_PORT=$(kubectl get svc "$LOKI_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "3100")
    echo_info "Found Loki service: $LOKI_SVC (port: $LOKI_PORT)"
else
    echo_error "Loki service not found"
fi

# Find Tempo service
echo ""
echo "Finding Tempo service..."
TEMPO_SVC=""
TEMPO_PORT=""
if kubectl get svc tempo -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
    TEMPO_SVC="tempo"
    # Tempo HTTP API is typically on port 3200 (not 6831 which is UDP)
    TEMPO_PORT=$(kubectl get svc "$TEMPO_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null)
    if [ -z "$TEMPO_PORT" ]; then
        # Check for port 3200 specifically (HTTP API)
        TEMPO_PORT_3200=$(kubectl get svc "$TEMPO_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.port==3200)].port}' 2>/dev/null)
        if [ -n "$TEMPO_PORT_3200" ]; then
            TEMPO_PORT="3200"
        else
            TEMPO_PORT=$(kubectl get svc "$TEMPO_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "3200")
            # If port is 6831 (UDP), use 3200 for HTTP API instead
            if [ "$TEMPO_PORT" = "6831" ]; then
                TEMPO_PORT="3200"
            fi
        fi
    fi
    echo_info "Found Tempo service: $TEMPO_SVC (port: $TEMPO_PORT)"
else
    echo_error "Tempo service not found"
fi

# Configure Loki datasource
if [ -n "$LOKI_SVC" ]; then
    echo ""
    echo "Configuring Loki datasource..."
    LOKI_URL="http://${LOKI_SVC}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:${LOKI_PORT}"

    LOKI_JSON=$(cat <<EOF
{
  "name": "Loki",
  "type": "loki",
  "url": "${LOKI_URL}",
  "access": "proxy",
  "uid": "loki",
  "editable": true,
  "jsonData": {
    "maxLines": 1000
  }
}
EOF
)

    # Check if exists
    EXISTING_LOKI=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
        "http://localhost:${LOCAL_PORT}/api/datasources/name/Loki" 2>/dev/null)

    if echo "$EXISTING_LOKI" | jq -e '.id' >/dev/null 2>&1; then
        # Update existing
        LOKI_ID=$(echo "$EXISTING_LOKI" | jq -r '.id')
        LOKI_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
            -u "admin:${GRAFANA_PASSWORD}" \
            -H "Content-Type: application/json" \
            -d "${LOKI_JSON}" \
            "http://localhost:${LOCAL_PORT}/api/datasources/${LOKI_ID}" 2>/dev/null)
        LOKI_HTTP_CODE=$(echo "$LOKI_RESPONSE" | tail -n1)
        if [ "$LOKI_HTTP_CODE" = "200" ]; then
            echo_info "Loki datasource updated (ID: $LOKI_ID)"
        else
            echo_error "Failed to update Loki datasource (HTTP $LOKI_HTTP_CODE)"
            echo "$LOKI_RESPONSE" | sed '$d' | jq -r '.message // .' 2>/dev/null || true
        fi
    else
        # Create new
        LOKI_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
            -u "admin:${GRAFANA_PASSWORD}" \
            -H "Content-Type: application/json" \
            -d "${LOKI_JSON}" \
            "http://localhost:${LOCAL_PORT}/api/datasources" 2>/dev/null)
        LOKI_HTTP_CODE=$(echo "$LOKI_RESPONSE" | tail -n1)
        if [ "$LOKI_HTTP_CODE" = "200" ] || [ "$LOKI_HTTP_CODE" = "201" ]; then
            echo_info "Loki datasource created"
            echo "$LOKI_RESPONSE" | sed '$d' | jq -r '.message // "Success"' 2>/dev/null || true
        else
            echo_error "Failed to create Loki datasource (HTTP $LOKI_HTTP_CODE)"
            echo "$LOKI_RESPONSE" | sed '$d' | jq -r '.message // .' 2>/dev/null || echo "$LOKI_RESPONSE" | sed '$d'
        fi
    fi
else
    echo_warn "Skipping Loki datasource (service not found)"
fi

# Configure Tempo datasource
if [ -n "$TEMPO_SVC" ]; then
    echo ""
    echo "Configuring Tempo datasource..."
    TEMPO_URL="http://${TEMPO_SVC}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:${TEMPO_PORT}"

    TEMPO_JSON=$(cat <<EOF
{
  "name": "Tempo",
  "type": "tempo",
  "url": "${TEMPO_URL}",
  "access": "proxy",
  "uid": "tempo",
  "editable": true,
  "jsonData": {
    "httpMethod": "GET",
    "serviceMap": {
      "datasourceUid": "prometheus"
    },
    "nodeGraph": {
      "enabled": true
    },
    "search": {
      "hide": false
    },
    "tracesToLogs": {
      "datasourceUid": "loki",
      "tags": ["job", "instance", "pod", "namespace", "service.name"],
      "mappedTags": [
        {
          "key": "service.name",
          "value": "service"
        }
      ],
      "mapTagNamesEnabled": false,
      "spanStartTimeShift": "1h",
      "spanEndTimeShift": "1h",
      "filterByTraceID": false,
      "filterBySpanID": false
    },
    "tracesToMetrics": {
      "datasourceUid": "prometheus",
      "tags": [
        {
          "key": "service.name",
          "value": "service"
        },
        {
          "key": "job"
        }
      ],
      "queries": [
        {
          "name": "Sample query",
          "query": "sum(rate(tempo_spanmetrics_latency_bucket{\${__tags}}[5m]))"
        }
      ]
    }
  }
}
EOF
)

    # Check if exists
    EXISTING_TEMPO=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
        "http://localhost:${LOCAL_PORT}/api/datasources/name/Tempo" 2>/dev/null)

    if echo "$EXISTING_TEMPO" | jq -e '.id' >/dev/null 2>&1; then
        # Update existing
        TEMPO_ID=$(echo "$EXISTING_TEMPO" | jq -r '.id')
        TEMPO_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
            -u "admin:${GRAFANA_PASSWORD}" \
            -H "Content-Type: application/json" \
            -d "${TEMPO_JSON}" \
            "http://localhost:${LOCAL_PORT}/api/datasources/${TEMPO_ID}" 2>/dev/null)
        TEMPO_HTTP_CODE=$(echo "$TEMPO_RESPONSE" | tail -n1)
        if [ "$TEMPO_HTTP_CODE" = "200" ]; then
            echo_info "Tempo datasource updated (ID: $TEMPO_ID)"
        else
            echo_error "Failed to update Tempo datasource (HTTP $TEMPO_HTTP_CODE)"
            echo "$TEMPO_RESPONSE" | sed '$d' | jq -r '.message // .' 2>/dev/null || true
        fi
    else
        # Create new
        TEMPO_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
            -u "admin:${GRAFANA_PASSWORD}" \
            -H "Content-Type: application/json" \
            -d "${TEMPO_JSON}" \
            "http://localhost:${LOCAL_PORT}/api/datasources" 2>/dev/null)
        TEMPO_HTTP_CODE=$(echo "$TEMPO_RESPONSE" | tail -n1)
        if [ "$TEMPO_HTTP_CODE" = "200" ] || [ "$TEMPO_HTTP_CODE" = "201" ]; then
            echo_info "Tempo datasource created"
            echo "$TEMPO_RESPONSE" | sed '$d' | jq -r '.message // "Success"' 2>/dev/null || true
        else
            echo_error "Failed to create Tempo datasource (HTTP $TEMPO_HTTP_CODE)"
            echo "$TEMPO_RESPONSE" | sed '$d' | jq -r '.message // .' 2>/dev/null || echo "$TEMPO_RESPONSE" | sed '$d'
        fi
    fi
else
    echo_warn "Skipping Tempo datasource (service not found)"
fi

# Verify datasources
echo ""
echo "Verifying datasources..."
ALL_DS=$(curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:${LOCAL_PORT}/api/datasources" 2>/dev/null)
DS_COUNT=$(echo "$ALL_DS" | jq -r 'length' 2>/dev/null || echo "0")
echo_info "Total datasources: $DS_COUNT"

echo "$ALL_DS" | jq -r '.[] | "  ✓ \(.name) (\(.type)) - \(.url)"' 2>/dev/null || echo "$ALL_DS" | jq -r '.[] | "\(.name): \(.type)"' 2>/dev/null

# Cleanup
kill $GRAFANA_PF_PID 2>/dev/null || true

echo ""
echo "=========================================="
echo "✅ Datasource configuration complete!"
echo "=========================================="
