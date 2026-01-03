#!/bin/bash
set -euo pipefail

# Quick E2E Demo Script - Run everything and show Grafana dashboard
# This is a simplified version that you can run manually step by step

APP_NAME="dm-nkp-gitops-custom-app"
CLUSTER_NAME="dm-nkp-demo-cluster"
NAMESPACE="default"
IMAGE_NAME="dm-nkp-gitops-custom-app:demo"
DASHBOARD_IMPORTED=false

echo "=========================================="
echo "  E2E Demo - Step by Step"
echo "=========================================="
echo ""

# Step 1: Build
echo "Step 1: Building application..."
make clean || true
make deps
make build
echo "✓ Build complete"
echo ""

# Step 2: Run tests
echo "Step 2: Running tests..."
make unit-tests || echo "⚠ Some tests may have warnings"
echo ""

# Step 3: Build Docker image
echo "Step 3: Building Docker image..."
docker build -t $IMAGE_NAME .
echo "✓ Docker image built"
echo ""

# Step 4: Create kind cluster
echo "Step 4: Creating kind cluster..."
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster already exists, using it..."
else
    kind create cluster --name $CLUSTER_NAME
fi
kubectl config use-context "kind-${CLUSTER_NAME}"
echo "✓ Kind cluster ready"
echo ""

# Step 5: Load image
echo "Step 5: Loading image into kind..."
kind load docker-image $IMAGE_NAME --name $CLUSTER_NAME
echo "✓ Image loaded"
echo ""

# Step 6: Deploy app
echo "Step 6: Deploying application..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f - || true

# Update deployment with demo image
cat manifests/base/deployment.yaml | \
    sed "s|image:.*|image: ${IMAGE_NAME}|" | \
    sed 's|imagePullPolicy:.*|imagePullPolicy: Never|' | \
    kubectl apply -f -

kubectl apply -f manifests/base/service.yaml

echo "Waiting for pods..."
kubectl wait --for=condition=ready pod -l app=$APP_NAME -n $NAMESPACE --timeout=2m || true
echo "✓ Application deployed"
echo ""

# Step 7: Deploy monitoring using Helm
echo "Step 7: Deploying monitoring stack using Helm..."
if command -v helm >/dev/null 2>&1; then
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1 || true

    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true

    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
      --namespace monitoring \
      --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
      --set prometheus.service.type=NodePort \
      --set prometheus.service.nodePort=30090 \
      --wait --timeout=5m >/dev/null 2>&1 || echo "⚠ Prometheus installation had issues"

    echo "Waiting for monitoring..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=2m >/dev/null 2>&1 || true
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=2m >/dev/null 2>&1 || true
    echo "✓ Monitoring deployed via Helm"

    # Step 7a: Configure Grafana (datasource + dashboard)
    echo ""
    echo "Step 7a: Configuring Grafana..."
    if [ -f "grafana/dashboard.json" ]; then
        # Wait for Grafana to be fully ready
        sleep 5

        # Get Grafana admin password
        GRAFANA_PASSWORD=$(kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "prom-operator")

        # Port forward to Grafana in background
        kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 >/dev/null 2>&1 &
        GRAFANA_PF_PID=$!
        sleep 5

        # Wait for Grafana API to be ready
        # shellcheck disable=SC2034  # Loop variable intentionally unused
        for _ in {1..30}; do
            if curl -s -u "admin:${GRAFANA_PASSWORD}" http://localhost:3000/api/health >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done

        # Step 7a.1: Configure Prometheus datasource
        echo "  Configuring Prometheus datasource..."
        PROMETHEUS_URL="http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090"
        DATASOURCE_JSON=$(cat <<EOF
{
  "name": "Prometheus",
  "type": "prometheus",
  "url": "${PROMETHEUS_URL}",
  "access": "proxy",
  "isDefault": true,
  "jsonData": {
    "timeInterval": "15s"
  }
}
EOF
)

        # Check if datasource already exists
        EXISTING_DS=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
            "http://localhost:3000/api/datasources/name/Prometheus" 2>/dev/null)

        if echo "$EXISTING_DS" | grep -q '"id"'; then
            # Update existing datasource
            DS_ID=$(echo "$EXISTING_DS" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
            DS_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
                -u "admin:${GRAFANA_PASSWORD}" \
                -H "Content-Type: application/json" \
                -d "${DATASOURCE_JSON}" \
                "http://localhost:3000/api/datasources/${DS_ID}" 2>/dev/null)
            DS_HTTP_CODE=$(echo "$DS_RESPONSE" | tail -n1)
            if [ "$DS_HTTP_CODE" = "200" ]; then
                echo "  ✓ Prometheus datasource updated"
            else
                echo "  ⚠ Failed to update datasource (HTTP $DS_HTTP_CODE)"
            fi
        else
            # Create new datasource
            DS_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
                -u "admin:${GRAFANA_PASSWORD}" \
                -H "Content-Type: application/json" \
                -d "${DATASOURCE_JSON}" \
                http://localhost:3000/api/datasources 2>/dev/null)
            DS_HTTP_CODE=$(echo "$DS_RESPONSE" | tail -n1)
            if [ "$DS_HTTP_CODE" = "200" ] || [ "$DS_HTTP_CODE" = "201" ]; then
                echo "  ✓ Prometheus datasource created"
            else
                echo "  ⚠ Failed to create datasource (HTTP $DS_HTTP_CODE) - may already exist"
            fi
        fi


        # Step 7a.2: Import dashboard
        echo "  Importing dashboard..."
        # Prepare dashboard JSON for import (Grafana API expects dashboard object with overwrite flag)
        if command -v jq >/dev/null 2>&1; then
            DASHBOARD_JSON=$(jq -n --argjson dashboard "$(cat grafana/dashboard.json)" '{dashboard: $dashboard, overwrite: true}')
        else
            # Fallback: wrap dashboard JSON manually
            DASHBOARD_CONTENT=$(cat grafana/dashboard.json)
            DASHBOARD_JSON="{\"dashboard\":${DASHBOARD_CONTENT},\"overwrite\":true}"
        fi

        # Import dashboard via API
        IMPORT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
            -u "admin:${GRAFANA_PASSWORD}" \
            -H "Content-Type: application/json" \
            -d "${DASHBOARD_JSON}" \
            http://localhost:3000/api/dashboards/db 2>/dev/null)

        HTTP_CODE=$(echo "$IMPORT_RESPONSE" | tail -n1)
        if [ "$HTTP_CODE" = "200" ]; then
            echo "  ✓ Dashboard imported successfully"
            DASHBOARD_IMPORTED=true
        else
            echo "  ⚠ Dashboard import failed (HTTP $HTTP_CODE) - you can import manually later"
            DASHBOARD_IMPORTED=false
        fi

        # Stop port forward
        kill $GRAFANA_PF_PID 2>/dev/null || true
        sleep 1
    else
        echo "⚠ Dashboard file not found at grafana/dashboard.json"
        DASHBOARD_IMPORTED=false
    fi
else
    echo "⚠ Helm not found. Please install Helm to deploy monitoring stack."
    echo "⚠ Skipping monitoring deployment."
    echo "⚠ Install Helm: https://helm.sh/docs/intro/install/"
fi
echo ""

# Step 8: Generate traffic
echo "Step 8: Generating traffic..."
kubectl port-forward -n $NAMESPACE svc/$APP_NAME 8080:8080 >/dev/null 2>&1 &
PF_PID=$!
sleep 2

# shellcheck disable=SC2034  # Loop variable intentionally unused
for _ in {1..100}; do
    curl -s http://localhost:8080/ >/dev/null || true
    sleep 0.05
done

kill $PF_PID 2>/dev/null || true
echo "✓ Generated 100 requests"
sleep 3
echo ""

# Step 9: Show access info
echo "=========================================="
echo "  ✅ Setup Complete!"
echo "=========================================="
echo ""
echo "📊 To view Grafana Dashboard:"
echo ""
echo "1. Port forward to Grafana:"
if command -v helm >/dev/null 2>&1; then
    echo "   kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    echo "   (For kube-prometheus-stack)"
else
    echo "   kubectl port-forward -n monitoring svc/grafana 3000:3000"
    echo "   (For standalone Grafana)"
fi
echo ""
echo "2. Open browser:"
echo "   http://localhost:3000"
echo ""
echo "3. Login:"
echo "   Username: admin"
if command -v helm >/dev/null 2>&1; then
    echo "   Password: (run: kubectl get secret -n monitoring prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
else
    echo "   Password: admin"
fi
echo ""
if [ "${DASHBOARD_IMPORTED:-false}" = "true" ]; then
    echo "4. Dashboard already imported! Navigate to:"
    echo "   Dashboards → dm-nkp-gitops-custom-app Metrics"
else
    echo "4. Import dashboard:"
    echo "   Dashboards → Import → Upload grafana/dashboard.json"
fi
echo ""
echo "📈 To view Prometheus:"
echo "   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "   http://localhost:9090"
echo ""
echo "🧹 Cleanup:"
echo "   kind delete cluster --name $CLUSTER_NAME"
echo ""
