#!/bin/bash
set -euo pipefail

# Script to set up monitoring stack using Helm charts
# Usage: ./scripts/setup-monitoring-helm.sh [cluster-name] [namespace]

CLUSTER_NAME="${1:-dm-nkp-demo-cluster}"
APP_NAMESPACE="${2:-default}"
MONITORING_NAMESPACE="monitoring"

echo "=========================================="
echo "  Setting up Monitoring Stack with Helm"
echo "=========================================="
echo "Application namespace: $APP_NAMESPACE"
echo "Monitoring namespace: $MONITORING_NAMESPACE"
echo ""

# Check prerequisites
command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed. Aborting." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed. Aborting." >&2; exit 1; }

# Set kubectl context
echo "Setting kubectl context..."
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || {
    echo "Cluster $CLUSTER_NAME not found. Please create it first."
    exit 1
}

# Add Helm repositories
echo ""
echo "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Create monitoring namespace
echo ""
echo "Creating monitoring namespace..."
kubectl create namespace $MONITORING_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Install Prometheus using kube-prometheus-stack (includes Prometheus + Grafana)
echo ""
echo "Installing Prometheus Operator (kube-prometheus-stack)..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace $MONITORING_NAMESPACE \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.retention=200h \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort=30090 \
  --wait --timeout=5m

# Note: kube-prometheus-stack already includes Grafana
# If you need standalone Grafana, uncomment below:
# echo ""
# echo "Installing standalone Grafana..."
# helm upgrade --install grafana grafana/grafana \
#   --namespace $MONITORING_NAMESPACE \
#   --set adminPassword=admin \
#   --set service.type=NodePort \
#   --set service.nodePort=30300 \
#   --set persistence.enabled=false \
#   --wait --timeout=5m

# Wait for pods
echo ""
echo "Waiting for monitoring stack to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n $MONITORING_NAMESPACE --timeout=5m || true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n $MONITORING_NAMESPACE --timeout=5m || true

# Get Grafana admin password
GRAFANA_PASSWORD=$(kubectl get secret -n $MONITORING_NAMESPACE prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")

# Get access information
echo ""
echo "=========================================="
echo "  Monitoring Stack Ready!"
echo "=========================================="
echo ""
echo "📊 Prometheus:"
echo "  kubectl port-forward -n $MONITORING_NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "  Or NodePort: http://<node-ip>:30090"
echo ""
echo "📈 Grafana:"
echo "  kubectl port-forward -n $MONITORING_NAMESPACE svc/prometheus-grafana 3000:80"
echo "  Or NodePort: http://<node-ip>:30300"
echo "  Username: admin"
echo "  Password: $GRAFANA_PASSWORD"
echo "  (Get password: kubectl get secret -n $MONITORING_NAMESPACE prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
echo ""
echo "📋 To import dashboard:"
echo "  1. Access Grafana UI"
echo "  2. Go to Dashboards → Import"
echo "  3. Upload grafana/dashboard.json"
echo "  4. Select Prometheus datasource"
echo ""
echo "🔍 Check ServiceMonitor for app metrics:"
echo "  kubectl get servicemonitor -n $MONITORING_NAMESPACE"
echo ""
