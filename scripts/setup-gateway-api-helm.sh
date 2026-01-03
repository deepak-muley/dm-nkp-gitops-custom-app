#!/bin/bash
set -euo pipefail

# Script to set up Gateway API with Traefik using Helm
# Usage: ./scripts/setup-gateway-api-helm.sh [cluster-name]

CLUSTER_NAME="${1:-dm-nkp-demo-cluster}"
TRAEFIK_NAMESPACE="traefik-system"

echo "=========================================="
echo "  Setting up Gateway API with Traefik"
echo "=========================================="
echo ""

# Check prerequisites
command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed. Aborting." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed. Aborting." >&2; exit 1; }

# Set kubectl context
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || {
    echo "Cluster $CLUSTER_NAME not found. Please create it first."
    exit 1
}

# Install Gateway API CRDs
echo "Installing Gateway API CRDs..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Wait for CRDs
echo "Waiting for Gateway API CRDs..."
kubectl wait --for condition=established --timeout=60s crd/gateways.gateway.networking.k8s.io || true

# Install Traefik with Gateway API support
echo ""
echo "Installing Traefik with Gateway API support..."
helm repo add traefik https://traefik.github.io/charts
helm repo update

kubectl create namespace $TRAEFIK_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install traefik traefik/traefik \
  --namespace $TRAEFIK_NAMESPACE \
  --set experimental.kubernetesGateway.enabled=true \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443 \
  --set service.type=NodePort \
  --wait --timeout=5m

echo ""
echo "=========================================="
echo "  Gateway API Ready!"
echo "=========================================="
echo ""
echo "✅ Gateway API CRDs installed"
echo "✅ Traefik configured with Gateway API support"
echo ""
echo "📋 Create Gateway:"
echo "  kubectl apply -f manifests/gateway-api/gateway.yaml"
echo ""
echo "📋 Create HTTPRoute:"
echo "  kubectl apply -f manifests/gateway-api/httproute.yaml"
echo ""

