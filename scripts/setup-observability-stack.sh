#!/bin/bash
# Script to set up the OpenTelemetry-based observability stack
# This includes: OTel Collector, Prometheus, Loki, Tempo, and Grafana

set -euo pipefail

NAMESPACE="observability"
OTEL_COLLECTOR_CHART="chart/observability-stack"

echo "Setting up OpenTelemetry-based Observability Stack..."

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "Error: helm is not installed"
    exit 1
fi

# Create namespace
echo "Creating namespace: ${NAMESPACE}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repositories
echo "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo update

# Install Prometheus (via kube-prometheus-stack which includes Grafana)
echo "Installing Prometheus and Grafana via kube-prometheus-stack..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace ${NAMESPACE} \
  --set prometheus.prometheusSpec.retention=30d \
  --set grafana.adminPassword=admin \
  --wait

# Install Loki
echo "Installing Loki for logs..."
helm upgrade --install loki grafana/loki-stack \
  --namespace ${NAMESPACE} \
  --set loki.enabled=true \
  --set promtail.enabled=true \
  --set grafana.enabled=false \
  --wait || {
    echo "Note: If loki-stack chart is deprecated, try installing Loki separately:"
    echo "  helm repo add grafana https://grafana.github.io/helm-charts"
    echo "  helm install loki grafana/loki --namespace ${NAMESPACE}"
  }

# Install Tempo
echo "Installing Tempo for traces..."
helm upgrade --install tempo grafana/tempo \
  --namespace ${NAMESPACE} \
  --set serviceAccount.create=true \
  --wait || {
    echo "Note: If tempo chart is not available, you may need to install it manually"
  }

# Install OpenTelemetry Collector
echo "Installing OpenTelemetry Collector..."
if [ -f "${OTEL_COLLECTOR_CHART}/Chart.yaml" ]; then
  helm upgrade --install otel-collector ${OTEL_COLLECTOR_CHART} \
    --namespace ${NAMESPACE} \
    --wait || {
      echo "Warning: Failed to install OTel Collector from local chart"
      echo "You may need to install it manually or use the official chart"
    }
else
  echo "Warning: Local OTel Collector chart not found. Installing from upstream..."
  helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts || true
  helm repo update
  helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
    --namespace ${NAMESPACE} \
    --wait || echo "Note: OTel Collector installation may need manual configuration"
fi

# Configure Grafana data sources (Prometheus, Loki, Tempo)
echo "Configuring Grafana data sources..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n ${NAMESPACE} --timeout=300s || true

# Wait for services to be ready
echo "Waiting for services to be ready..."
sleep 10

# Configure Grafana dashboard discovery (if kube-prometheus-stack)
echo ""
echo "Configuring Grafana dashboard discovery..."
kubectl create configmap -n ${NAMESPACE} grafana-dashboard-provider \
  --from-literal=dashboards.yaml="
apiVersion: 1
providers:
- name: 'App Dashboards'
  orgId: 1
  folder: ''
  type: file
  disableDeletion: false
  editable: true
  allowUiUpdates: true
  options:
    path: /var/lib/grafana/dashboards
" --dry-run=client -o yaml | kubectl apply -f - || {
  echo "Note: Grafana dashboard provider ConfigMap may already exist or needs manual configuration"
}

# Get service endpoints
echo ""
echo "=========================================="
echo "Observability Stack Setup Complete!"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This observability stack is for LOCAL TESTING ONLY"
echo "In production, these services are pre-deployed by the platform team"
echo ""
echo "Services:"
kubectl get svc -n ${NAMESPACE}
echo ""
echo "To access Grafana:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/prometheus-grafana 3000:80"
echo "  URL: http://localhost:3000"
echo "  Username: admin"
echo "  Password: admin"
echo ""
echo "To access Prometheus:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "  URL: http://localhost:9090"
echo ""
echo "OpenTelemetry Collector OTLP endpoint:"
echo "  gRPC: otel-collector.${NAMESPACE}.svc.cluster.local:4317"
echo "  HTTP: otel-collector.${NAMESPACE}.svc.cluster.local:4318"
echo ""
echo "Next Steps:"
echo "  1. Deploy your application with OpenTelemetry enabled"
echo "  2. Application chart will deploy Grafana dashboards automatically"
echo "  3. Configure Grafana to discover dashboards from ConfigMaps (may need manual setup)"
echo ""
echo "Configure your application with:"
echo "  OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector.${NAMESPACE}.svc.cluster.local:4317"
echo "  OTEL_SERVICE_NAME=your-service-name"
echo ""
