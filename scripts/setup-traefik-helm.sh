#!/bin/bash
set -euo pipefail

# Script to set up Traefik using Helm chart
# Usage: ./scripts/setup-traefik-helm.sh [cluster-name] [namespace]

CLUSTER_NAME="${1:-dm-nkp-demo-cluster}"
TRAEFIK_NAMESPACE="traefik-system"

echo "=========================================="
echo "  Setting up Traefik with Helm"
echo "=========================================="
echo "Traefik namespace: $TRAEFIK_NAMESPACE"
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

# Add Helm repository
echo ""
echo "Adding Traefik Helm repository..."
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Create namespace
echo ""
echo "Creating traefik namespace..."
kubectl create namespace $TRAEFIK_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Install Traefik
echo ""
echo "Installing Traefik..."
helm upgrade --install traefik traefik/traefik \
  --namespace $TRAEFIK_NAMESPACE \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443 \
  --set service.type=NodePort \
  --set ingressClass.enabled=true \
  --set ingressClass.isDefaultClass=true \
  --wait --timeout=5m

# Wait for Traefik to be ready
echo ""
echo "Waiting for Traefik to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n $TRAEFIK_NAMESPACE --timeout=5m

echo ""
echo "=========================================="
echo "  Traefik Ready!"
echo "=========================================="
echo ""
echo "🌐 Access Traefik:"
echo "  kubectl port-forward -n $TRAEFIK_NAMESPACE svc/traefik 8080:80"
echo "  Or NodePort: http://<node-ip>:30080"
echo ""
echo "📋 Traefik Dashboard:"
echo "  http://localhost:8080/dashboard/"
echo ""
echo "✅ Traefik is now ready to handle IngressRoute resources"
echo ""
