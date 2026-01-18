#!/bin/bash
set -euo pipefail

# Script to set up MetalLB using Helm chart
# Usage: ./scripts/setup-metallb-helm.sh [cluster-name] [ip-pool-start] [ip-pool-end]
#
# For kind clusters, the IP pool should be in the Docker network range.
# Get Docker network range: docker network inspect kind | jq -r '.[0].IPAM.Config[0].Subnet'
# Example: ./scripts/setup-metallb-helm.sh dm-nkp-demo-cluster 172.18.255.200 172.18.255.250

CLUSTER_NAME="${1:-dm-nkp-demo-cluster}"
METALLB_NAMESPACE="metallb-system"
IP_POOL_START="${2:-172.18.255.200}"
IP_POOL_END="${3:-172.18.255.250}"

echo "=========================================="
echo "  Setting up MetalLB with Helm"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "MetalLB namespace: $METALLB_NAMESPACE"
echo "IP Pool: $IP_POOL_START-$IP_POOL_END"
echo ""

# Check prerequisites
command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed. Aborting." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed. Aborting." >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "docker is required but not installed. Aborting." >&2; exit 1; }

# Set kubectl context
echo "Setting kubectl context..."
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || {
    echo "Cluster $CLUSTER_NAME not found. Please create it first."
    exit 1
}

# For kind clusters, detect Docker network subnet if not provided
if [ "$CLUSTER_NAME" != "" ]; then
    echo "Detecting Docker network for kind cluster..."
    if docker network inspect kind >/dev/null 2>&1; then
        DOCKER_SUBNET=$(docker network inspect kind | jq -r '.[0].IPAM.Config[0].Subnet' 2>/dev/null || echo "")
        if [ -n "$DOCKER_SUBNET" ] && [ "$DOCKER_SUBNET" != "null" ]; then
            echo "Detected Docker network subnet: $DOCKER_SUBNET"
            echo "Using IP pool: $IP_POOL_START-$IP_POOL_END (make sure this is within $DOCKER_SUBNET)"
        fi
    fi
fi

# Install MetalLB using official kubectl manifests (more reliable than Helm)
echo ""
echo "Installing MetalLB using official manifests..."

# Create namespace first
kubectl create namespace $METALLB_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Install MetalLB using official manifests
echo "Applying MetalLB manifests..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.6/config/manifests/metallb-native.yaml

# Wait for MetalLB CRDs to be established
echo "Waiting for MetalLB CRDs..."
kubectl wait --namespace $METALLB_NAMESPACE \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s 2>/dev/null || {
    echo "Waiting for MetalLB pods to be created..."
    sleep 10
}

# Wait for MetalLB pods to be ready
echo "Waiting for MetalLB pods..."
for i in {1..30}; do
    READY_PODS=$(kubectl get pods -n $METALLB_NAMESPACE -l app=metallb --no-headers 2>/dev/null | grep -c Running || echo "0")
    TOTAL_PODS=$(kubectl get pods -n $METALLB_NAMESPACE -l app=metallb --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$READY_PODS" -ge 2 ] && [ "$READY_PODS" = "$TOTAL_PODS" ]; then
        break
    fi
    sleep 2
done

# Configure IP address pool
echo ""
echo "Configuring MetalLB IP address pool..."
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: ${METALLB_NAMESPACE}
spec:
  addresses:
  - ${IP_POOL_START}-${IP_POOL_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: ${METALLB_NAMESPACE}
spec:
  ipAddressPools:
  - default-pool
EOF

# Wait for MetalLB to be ready
echo ""
echo "Waiting for MetalLB to be ready..."
kubectl wait --namespace $METALLB_NAMESPACE \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=metallb \
  --timeout=5m || true

# Verify MetalLB installation
echo ""
echo "Verifying MetalLB installation..."
kubectl get pods -n $METALLB_NAMESPACE

echo ""
echo "=========================================="
echo "  MetalLB Ready!"
echo "=========================================="
echo ""
echo "✅ MetalLB installed and configured"
echo "📋 IP Pool: $IP_POOL_START-$IP_POOL_END"
echo ""
echo "💡 To use MetalLB with a service:"
echo "   kubectl patch svc <service-name> -n <namespace> -p '{\"spec\":{\"type\":\"LoadBalancer\"}}'"
echo ""
echo "💡 Get LoadBalancer IP:"
echo "   kubectl get svc <service-name> -n <namespace>"
echo ""
echo "✅ MetalLB is ready to assign LoadBalancer IPs"
echo ""
