#!/bin/bash
# Script to reinstall Tempo datasource in Grafana

set -e

OBSERVABILITY_NAMESPACE="${OBSERVABILITY_NAMESPACE:-observability}"

echo "=========================================="
echo "Reinstalling Tempo Datasource in Grafana"
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

# Find Tempo service
echo ""
echo "Step 3: Finding Tempo service..."
TEMPO_SVC=""
TEMPO_PORT=""

if kubectl get svc tempo -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
    TEMPO_SVC="tempo"
    # Try to find HTTP port (3200 is the standard Tempo HTTP API port)
    TEMPO_PORT=$(kubectl get svc tempo -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.port==3200)].port}' 2>/dev/null)
    if [ -z "$TEMPO_PORT" ]; then
        TEMPO_PORT=$(kubectl get svc tempo -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null)
    fi
    if [ -z "$TEMPO_PORT" ]; then
        TEMPO_PORT="3200"  # Default Tempo HTTP API port
    fi
elif kubectl get svc -n $OBSERVABILITY_NAMESPACE | grep -i tempo | head -1; then
    TEMPO_SVC=$(kubectl get svc -n $OBSERVABILITY_NAMESPACE | grep -i tempo | head -1 | awk '{print $1}')
    TEMPO_PORT=$(kubectl get svc $TEMPO_SVC -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null)
    if [ -z "$TEMPO_PORT" ]; then
        TEMPO_PORT=$(kubectl get svc $TEMPO_SVC -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "3200")
    fi
else
    echo "❌ Error: Tempo service not found in namespace $OBSERVABILITY_NAMESPACE"
    kill $GRAFANA_PF_PID 2>/dev/null || true
    exit 1
fi

echo "✅ Found Tempo service: $TEMPO_SVC (port: $TEMPO_PORT)"

# Find Prometheus and Loki UIDs for correlation
echo ""
echo "Step 4: Finding Prometheus and Loki datasource UIDs..."
PROMETHEUS_UID=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
    "http://localhost:3000/api/datasources/name/Prometheus" 2>/dev/null | jq -r '.uid' 2>/dev/null || echo "")

LOKI_UID=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
    "http://localhost:3000/api/datasources/name/Loki" 2>/dev/null | jq -r '.uid' 2>/dev/null || echo "")

echo "  Prometheus UID: ${PROMETHEUS_UID:-not found}"
echo "  Loki UID: ${LOKI_UID:-not found}"

# Configure Tempo datasource
echo ""
echo "Step 5: Configuring Tempo datasource..."
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
      "datasourceUid": "${PROMETHEUS_UID:-prometheus}"
    },
    "nodeGraph": {
      "enabled": true
    },
    "search": {
      "hide": false
    },
    "tracesToLogs": {
      "datasourceUid": "${LOKI_UID:-loki}",
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
      "datasourceUid": "${PROMETHEUS_UID:-prometheus}",
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

# Check if Tempo datasource already exists
EXISTING_TEMPO=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
    "http://localhost:3000/api/datasources/name/Tempo" 2>/dev/null)

if echo "$EXISTING_TEMPO" | grep -q '"id"'; then
    # Update existing datasource
    echo "  Updating existing Tempo datasource..."
    TEMPO_ID=$(echo "$EXISTING_TEMPO" | jq -r '.id' 2>/dev/null)
    TEMPO_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
        -u "admin:${GRAFANA_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d "${TEMPO_JSON}" \
        "http://localhost:3000/api/datasources/${TEMPO_ID}" 2>/dev/null)
    TEMPO_HTTP_CODE=$(echo "$TEMPO_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$TEMPO_RESPONSE" | sed '$d')

    if [ "$TEMPO_HTTP_CODE" = "200" ]; then
        echo "✅ Tempo datasource updated successfully"
    else
        echo "⚠️  Failed to update Tempo datasource (HTTP $TEMPO_HTTP_CODE)"
        echo "Response: $RESPONSE_BODY" | jq -r '.' 2>/dev/null || echo "$RESPONSE_BODY"
    fi
else
    # Create new datasource
    echo "  Creating new Tempo datasource..."
    TEMPO_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -u "admin:${GRAFANA_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d "${TEMPO_JSON}" \
        "http://localhost:3000/api/datasources" 2>/dev/null)
    TEMPO_HTTP_CODE=$(echo "$TEMPO_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$TEMPO_RESPONSE" | sed '$d')

    if [ "$TEMPO_HTTP_CODE" = "200" ] || [ "$TEMPO_HTTP_CODE" = "201" ]; then
        echo "✅ Tempo datasource created successfully"
    else
        echo "❌ Failed to create Tempo datasource (HTTP $TEMPO_HTTP_CODE)"
        echo "Response: $RESPONSE_BODY" | jq -r '.' 2>/dev/null || echo "$RESPONSE_BODY"
        kill $GRAFANA_PF_PID 2>/dev/null || true
        exit 1
    fi
fi

# Verify Tempo datasource
echo ""
echo "Step 6: Verifying Tempo datasource..."
VERIFY_TEMPO=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
    "http://localhost:3000/api/datasources/name/Tempo" 2>/dev/null)

if echo "$VERIFY_TEMPO" | grep -q '"id"'; then
    TEMPO_UID=$(echo "$VERIFY_TEMPO" | jq -r '.uid' 2>/dev/null)
    TEMPO_URL_VERIFY=$(echo "$VERIFY_TEMPO" | jq -r '.url' 2>/dev/null)
    echo "✅ Tempo datasource verified"
    echo "  UID: $TEMPO_UID"
    echo "  URL: $TEMPO_URL_VERIFY"

    # Test Tempo query
    echo ""
    echo "Step 7: Testing Tempo query..."
    TEMPO_RESULT=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
        "http://localhost:3000/api/datasources/proxy/uid/${TEMPO_UID}/api/search?limit=5" 2>/dev/null)

    TRACE_COUNT=$(echo "$TEMPO_RESULT" | jq -r '.traces | length' 2>/dev/null || echo "0")

    if [ "$TRACE_COUNT" -gt 0 ] 2>/dev/null; then
        echo "✅ Tempo query successful - Found $TRACE_COUNT traces"
        echo "  Sample trace IDs:"
        echo "$TEMPO_RESULT" | jq -r '.traces[]?.traceID' 2>/dev/null | head -3 | while read trace_id; do
            echo "    - $trace_id"
        done
    else
        echo "⚠️  Tempo query successful but no traces found (this is normal if no traffic has been generated)"
    fi
else
    echo "❌ Failed to verify Tempo datasource"
fi

# Cleanup
kill $GRAFANA_PF_PID 2>/dev/null || true

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Tempo datasource has been reinstalled"
echo ""
echo "Configuration:"
echo "  Name: Tempo"
echo "  URL: $TEMPO_URL"
echo "  UID: tempo"
echo ""
echo "Next steps:"
echo "1. Open Grafana: http://localhost:3000"
echo "2. Go to Configuration → Data Sources"
echo "3. Verify Tempo datasource is listed"
echo "4. Test it: Go to Explore → Select Tempo"
echo "5. Generate load: ./scripts/generate-load.sh"
echo "6. Check traces dashboard: dm-nkp-gitops-custom-app - Traces"
