#!/bin/bash
set -euo pipefail

# Script to fix MetalLB ImagePullBackOff issues by reinstalling using official manifests
# Usage: ./scripts/fix-metallb.sh [cluster-name] [ip-pool-start] [ip-pool-end]

CLUSTER_NAME="${1:-dm-nkp-demo-cluster}"
METALLB_NAMESPACE="metallb-system"
IP_POOL_START="${2:-172.18.255.200}"
IP_POOL_END="${3:-172.18.255.250}"

echo "=========================================="
echo "  Fixing MetalLB Installation"
echo "=========================================="
echo ""

# Set kubectl context
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || {
    echo "❌ Cluster $CLUSTER_NAME not found"
    exit 1
}

# Detect Docker network subnet for kind cluster
if docker network inspect kind >/dev/null 2>&1; then
    DOCKER_SUBNET=$(docker network inspect kind | jq -r '.[0].IPAM.Config[0].Subnet' 2>/dev/null || echo "")
    if [ -n "$DOCKER_SUBNET" ] && [ "$DOCKER_SUBNET" != "null" ]; then
        echo "Detected Docker network subnet: $DOCKER_SUBNET"
        # Try to extract base IP from subnet
        if [[ "$DOCKER_SUBNET" =~ ^([0-9]+\.[0-9]+)\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            BASE_IP="${BASH_REMATCH[1]}"
            IP_POOL_START="${BASE_IP}.255.200"
            IP_POOL_END="${BASE_IP}.255.250"
        fi
    fi
fi

echo "Using IP pool: $IP_POOL_START-$IP_POOL_END"
echo ""

# Step 1: Uninstall existing MetalLB Helm installation (if exists)
echo "Step 1: Removing existing MetalLB installation..."
if helm list -n $METALLB_NAMESPACE 2>/dev/null | grep -qE "^metallb[[:space:]]"; then
    echo "Uninstalling MetalLB Helm release..."
    helm uninstall metallb -n $METALLB_NAMESPACE 2>/dev/null || true
    sleep 5
fi

# Step 2: Delete existing MetalLB resources
echo "Step 2: Cleaning up existing MetalLB resources..."
kubectl delete ipaddresspool --all -n $METALLB_NAMESPACE 2>/dev/null || true
kubectl delete l2advertisement --all -n $METALLB_NAMESPACE 2>/dev/null || true
kubectl delete deployment -l app=metallb -n $METALLB_NAMESPACE 2>/dev/null || true
kubectl delete daemonset -l app=metallb -n $METALLB_NAMESPACE 2>/dev/null || true
kubectl delete pods -l app=metallb -n $METALLB_NAMESPACE 2>/dev/null || true
kubectl delete pods -l app.kubernetes.io/name=metallb -n $METALLB_NAMESPACE 2>/dev/null || true

# Wait for resources to be deleted
sleep 5

# Step 3: Delete namespace (will be recreated)
echo "Step 3: Cleaning up namespace..."
kubectl delete namespace $METALLB_NAMESPACE 2>/dev/null || true
sleep 3

# Step 4: Install MetalLB using official manifests
echo ""
echo "Step 4: Installing MetalLB using official manifests..."

# Create namespace
kubectl create namespace $METALLB_NAMESPACE

# Install MetalLB using official manifests
echo "Applying MetalLB manifests..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.6/config/manifests/metallb-native.yaml

# Wait for MetalLB CRDs
echo "Waiting for MetalLB CRDs to be established..."
kubectl wait --for=condition=established --timeout=60s crd/ipaddresspools.metallb.io 2>/dev/null || true
kubectl wait --for=condition=established --timeout=60s crd/l2advertisements.metallb.io 2>/dev/null || true

# Wait for MetalLB pods to be created and ready
echo "Waiting for MetalLB pods to be ready..."
for i in {1..60}; do
    READY_PODS=$(kubectl get pods -n $METALLB_NAMESPACE -l app=metallb --no-headers 2>/dev/null | grep -c Running || echo "0")
    TOTAL_PODS=$(kubectl get pods -n $METALLB_NAMESPACE -l app=metallb --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [ "$TOTAL_PODS" -eq 0 ]; then
        echo "Waiting for pods to be created... ($i/60)"
        sleep 2
        continue
    fi

    if [ "$READY_PODS" -ge 2 ] && [ "$READY_PODS" = "$TOTAL_PODS" ]; then
        echo "✅ MetalLB pods are ready ($READY_PODS/$TOTAL_PODS)"
        break
    else
        echo "Waiting for pods to be ready... ($READY_PODS/$TOTAL_PODS) ($i/60)"
        # Show pod status
        kubectl get pods -n $METALLB_NAMESPACE -l app=metallb 2>/dev/null | tail -3 || true
    fi

    if [ $i -eq 60 ]; then
        echo "⚠️  MetalLB pods not fully ready after 2 minutes"
        echo "Checking pod status..."
        kubectl get pods -n $METALLB_NAMESPACE -l app=metallb
        kubectl describe pods -n $METALLB_NAMESPACE -l app=metallb | grep -A 5 "Events:" | head -20
    fi
    sleep 2
done

# Step 5: Configure IP address pool
echo ""
echo "Step 5: Configuring MetalLB IP address pool..."
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

echo "✅ IP address pool configured"

# Verify installation
echo ""
echo "=========================================="
echo "  Verification"
echo "=========================================="
echo ""
echo "MetalLB pods:"
kubectl get pods -n $METALLB_NAMESPACE -l app=metallb

echo ""
echo "IP Address Pool:"
kubectl get ipaddresspool -n $METALLB_NAMESPACE

echo ""
echo "L2 Advertisement:"
kubectl get l2advertisement -n $METALLB_NAMESPACE

echo ""
echo "=========================================="
echo "  ✅ MetalLB Fixed!"
echo "=========================================="
echo ""
echo "To test LoadBalancer assignment:"
echo "  kubectl patch svc traefik -n traefik-system -p '{\"spec\":{\"type\":\"LoadBalancer\"}}'"
echo ""
echo "Check LoadBalancer IP:"
echo "  kubectl get svc traefik -n traefik-system"
echo ""
