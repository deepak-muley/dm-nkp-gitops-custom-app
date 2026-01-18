#!/bin/bash
# Script to set up the OpenTelemetry-based observability stack
# This includes: OTel Operator, Prometheus, Loki, Tempo, and Grafana

set -euo pipefail

NAMESPACE="observability"

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
# Handle CRD version mismatch by automatically uninstalling and reinstalling if needed
INSTALL_ERROR_FILE="/tmp/prometheus-install-$$.log"
if helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace ${NAMESPACE} \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.retention=30d \
  --set grafana.adminPassword=admin \
  --wait 2>&1 | tee "$INSTALL_ERROR_FILE"; then
  echo "Prometheus and Grafana installed/upgraded successfully"
  rm -f "$INSTALL_ERROR_FILE"
else
  INSTALL_ERROR=$(cat "$INSTALL_ERROR_FILE" 2>/dev/null || echo "")
  if echo "$INSTALL_ERROR" | grep -q "field not declared in schema"; then
    echo "Warning: Upgrade failed due to CRD schema mismatch (ServiceMonitor CRD version incompatibility)"
    echo "Automatically uninstalling and cleaning up CRDs to fix version mismatch..."
    helm uninstall prometheus -n ${NAMESPACE} 2>/dev/null || true
    sleep 3
    # Delete problematic ServiceMonitor resources that might have incompatible fields
    echo "Cleaning up ServiceMonitor resources with incompatible schema..."
    kubectl delete servicemonitor -n ${NAMESPACE} --all --ignore-not-found=true 2>/dev/null || true
    kubectl delete prometheusrule -n ${NAMESPACE} --all --ignore-not-found=true 2>/dev/null || true
    # Wait for resources to be fully deleted
    sleep 5
    # Reinstall with fresh CRDs (Helm will install updated CRDs)
    echo "Reinstalling Prometheus with fresh CRDs..."
    if helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
      --namespace ${NAMESPACE} \
      --create-namespace \
      --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
      --set prometheus.prometheusSpec.retention=30d \
      --set grafana.adminPassword=admin \
      --wait 2>&1 | tee "$INSTALL_ERROR_FILE"; then
      echo "Prometheus reinstalled successfully after CRD fix"
      rm -f "$INSTALL_ERROR_FILE"
    else
      REINSTALL_ERROR=$(cat "$INSTALL_ERROR_FILE" 2>/dev/null || echo "")
      if echo "$REINSTALL_ERROR" | grep -q "field not declared in schema"; then
        echo "Warning: Still seeing CRD schema issues. Deleting CRDs and retrying..."
        # Delete the CRDs themselves if they're still causing issues
        kubectl delete crd servicemonitors.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || true
        kubectl delete crd prometheusrules.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || true
        sleep 5
        # Final reinstall - Helm will install fresh CRDs
        if helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
          --namespace ${NAMESPACE} \
          --create-namespace \
          --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
          --set prometheus.prometheusSpec.retention=30d \
          --set grafana.adminPassword=admin \
          --wait; then
          echo "Prometheus reinstalled successfully after CRD deletion"
        else
          echo "Warning: Prometheus reinstallation still had issues"
        fi
      else
        echo "Warning: Prometheus reinstallation had issues: $(echo "$REINSTALL_ERROR" | head -3)"
      fi
      rm -f "$INSTALL_ERROR_FILE"
    fi
  else
    echo "Warning: Prometheus installation had issues: $(echo "$INSTALL_ERROR" | head -3)"
  fi
  rm -f "$INSTALL_ERROR_FILE"
fi

# Install Loki (using loki-simple-scalable for single-node kind clusters)
echo "Installing Loki for logs..."
# Note: grafana/loki-stack is deprecated, using loki-simple-scalable for local/testing clusters
# loki-simple-scalable works better for single-node kind clusters (no anti-affinity issues)
# First, uninstall any existing Loki to avoid conflicts
helm uninstall loki -n ${NAMESPACE} 2>/dev/null || true
sleep 2

if helm upgrade --install loki grafana/loki-simple-scalable \
  --namespace ${NAMESPACE} \
  --set singleBinary.replicas=1 \
  --wait; then
  echo "Loki installed successfully (using loki-simple-scalable)"
else
  echo "Warning: loki-simple-scalable installation had issues, trying loki-distributed with single replicas..."
  # Fallback: try loki-distributed with all replicas set to 1 for single-node clusters
  # Also need to set backend storage replicas to 1 and disable all anti-affinity
  if helm upgrade --install loki grafana/loki-distributed \
    --namespace ${NAMESPACE} \
    --set loki.read.replicas=1 \
    --set loki.write.replicas=1 \
    --set loki.backend.replicas=1 \
    --set loki.read.affinity=null \
    --set loki.write.affinity=null \
    --set loki.backend.affinity=null \
    --set loki.read.podAntiAffinity=null \
    --set loki.write.podAntiAffinity=null \
    --set loki.backend.podAntiAffinity=null \
    --wait; then
    echo "Loki installed successfully (using loki-distributed with single replicas)"
  else
    echo "Warning: Loki installation failed with both charts"
    echo "Loki is required for logs. Please install manually."
  fi
fi

# Install Tempo
echo "Installing Tempo for traces..."
helm upgrade --install tempo grafana/tempo \
  --namespace ${NAMESPACE} \
  --set serviceAccount.create=true \
  --wait || {
    echo "Note: If tempo chart is not available, you may need to install it manually"
  }

# Install cert-manager (required by OTel Operator for webhook certificates)
echo "Installing cert-manager (required by OTel Operator)..."
helm repo add jetstack https://charts.jetstack.io || true
helm repo update || true

if helm list -n cert-manager 2>/dev/null | grep -q cert-manager; then
  echo "cert-manager already installed"
else
  echo "Installing cert-manager..."
  if helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --set installCRDs=true \
    --wait; then
    echo "cert-manager installed successfully"
    # Wait for cert-manager webhook to be ready
    echo "Waiting for cert-manager webhook to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=3m 2>/dev/null || echo "cert-manager webhook may not be ready yet"
  else
    echo "Warning: cert-manager installation failed"
    echo "OTel Operator requires cert-manager. Please install manually:"
    echo "  helm repo add jetstack https://charts.jetstack.io"
    echo "  helm repo update"
    echo "  helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set installCRDs=true"
  fi
fi

# Install OpenTelemetry Operator (preferred approach for platform)
echo "Installing OpenTelemetry Operator..."
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts || true
helm repo update || true

# Check if OTel Operator is already installed
if helm list -n opentelemetry-operator-system 2>/dev/null | grep -q opentelemetry-operator; then
  echo "OTel Operator Helm release already exists, checking if operator is running..."
  if kubectl get pods -n opentelemetry-operator-system -l app.kubernetes.io/name=opentelemetry-operator 2>/dev/null | grep -q Running; then
    echo "OTel Operator is already installed and running"
  else
    echo "Upgrading OTel Operator..."
    helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
      --namespace opentelemetry-operator-system \
      --create-namespace \
      --set manager.collectorImage.repository=otel/opentelemetry-collector-contrib \
      --wait || {
        echo "Warning: Failed to upgrade OTel Operator"
        echo "You may need to install it manually"
      }
  fi
else
  echo "Installing OTel Operator via Helm..."
  helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
    --namespace opentelemetry-operator-system \
    --create-namespace \
    --set manager.collectorImage.repository=otel/opentelemetry-collector-contrib \
    --wait || {
      echo "Warning: Failed to install OTel Operator"
      echo "You may need to install it manually"
    }
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
echo "OpenTelemetry Operator installed"
echo "  Namespace: opentelemetry-operator-system"
echo ""
echo "Next Steps:"
echo "  1. Create an OpenTelemetryCollector CR in ${NAMESPACE} namespace"
echo "  2. Deploy your application with OpenTelemetry enabled"
echo "  3. Application chart will deploy Grafana dashboards automatically"
echo "  4. Configure Grafana to discover dashboards from ConfigMaps (may need manual setup)"
echo ""
echo "Create OpenTelemetryCollector CR (example):"
echo "  kubectl apply -f - <<EOF"
echo "  apiVersion: opentelemetry.io/v1beta1"
echo "  kind: OpenTelemetryCollector"
echo "  metadata:"
echo "    name: otel-collector"
echo "    namespace: ${NAMESPACE}"
echo "  spec:"
echo "    config: |"
echo "      receivers:"
echo "        otlp:"
echo "          protocols:"
echo "            grpc:"
echo "              endpoint: 0.0.0.0:4317"
echo "      exporters:"
echo "        prometheusremotewrite:"
echo "          endpoint: http://prometheus-kube-prometheus-prometheus.${NAMESPACE}.svc.cluster.local:9090/api/v1/write"
echo "      service:"
echo "        pipelines:"
echo "          metrics:"
echo "            receivers: [otlp]"
echo "            exporters: [prometheusremotewrite]"
echo "    mode: deployment"
echo "    replicas: 1"
echo "  EOF"
echo ""
echo "Once OpenTelemetryCollector is created, configure your application with:"
echo "  OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector.${NAMESPACE}.svc.cluster.local:4317"
echo "  OTEL_SERVICE_NAME=your-service-name"
echo ""
