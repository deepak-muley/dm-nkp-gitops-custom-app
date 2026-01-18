#!/bin/bash
set -euo pipefail

# Script to verify LoadBalancer IP and provide access instructions
# Usage: ./scripts/verify-access.sh [cluster-name]

CLUSTER_NAME="${1:-dm-nkp-demo-cluster}"
TRAEFIK_NAMESPACE="traefik-system"
APP_NAMESPACE="${APP_NAMESPACE:-default}"
APP_NAME="dm-nkp-gitops-custom-app"

echo "=========================================="
echo "  Access Verification & Instructions"
echo "=========================================="
echo ""

# Check if kind cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "❌ Kind cluster '$CLUSTER_NAME' not found"
    echo "   Run: ./scripts/e2e-demo-otel.sh"
    exit 1
fi

# Set kubectl context
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || {
    echo "❌ Failed to set kubectl context"
    exit 1
}

echo "✅ Cluster: $CLUSTER_NAME"
echo ""

# Check MetalLB status
echo "📋 Checking MetalLB status..."
if kubectl get pods -n metallb-system >/dev/null 2>&1; then
    METALLB_PODS=$(kubectl get pods -n metallb-system --no-headers 2>/dev/null | grep -c Running || echo "0")
    if [ "$METALLB_PODS" -gt 0 ]; then
        echo "   ✅ MetalLB is running ($METALLB_PODS pod(s))"
    else
        echo "   ⚠️  MetalLB pods not running"
    fi
else
    echo "   ⚠️  MetalLB namespace not found"
fi

# Check Traefik service type and IP
echo ""
echo "📋 Checking Traefik service..."
TRAEFIK_SVC_TYPE=$(kubectl get svc traefik -n $TRAEFIK_NAMESPACE -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
TRAEFIK_LB_IP=$(kubectl get svc traefik -n $TRAEFIK_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
TRAEFIK_NODEPORT=$(kubectl get svc traefik -n $TRAEFIK_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}' 2>/dev/null || echo "")

if [ "$TRAEFIK_SVC_TYPE" = "LoadBalancer" ]; then
    if [ -n "$TRAEFIK_LB_IP" ]; then
        echo "   ✅ Service Type: LoadBalancer"
        echo "   ✅ External IP: $TRAEFIK_LB_IP"
    else
        echo "   ✅ Service Type: LoadBalancer"
        echo "   ⚠️  External IP: Pending (may take a moment)"
    fi
elif [ "$TRAEFIK_SVC_TYPE" = "NodePort" ]; then
    echo "   ⚠️  Service Type: NodePort"
    if [ -n "$TRAEFIK_NODEPORT" ]; then
        NODE_IP=$(docker inspect ${CLUSTER_NAME}-control-plane --format='{{.NetworkSettings.Networks.kind.IPAddress}}' 2>/dev/null || echo "localhost")
        echo "   ℹ️  NodePort: $TRAEFIK_NODEPORT"
        echo "   ℹ️  Node IP: $NODE_IP"
    fi
else
    echo "   ⚠️  Service Type: $TRAEFIK_SVC_TYPE"
fi

# Check HTTPRoute status
echo ""
echo "📋 Checking HTTPRoute status..."
if kubectl get httproute -n $APP_NAMESPACE >/dev/null 2>&1; then
    HTTPROUTE_NAME=$(kubectl get httproute -n $APP_NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$HTTPROUTE_NAME" ]; then
        HTTPROUTE_ACCEPTED=$(kubectl get httproute $HTTPROUTE_NAME -n $APP_NAMESPACE -o jsonpath='{.status.parents[*].conditions[?(@.type=="Accepted")].status}' 2>/dev/null | grep -o True || echo "")
        if [ -n "$HTTPROUTE_ACCEPTED" ]; then
            echo "   ✅ HTTPRoute '$HTTPROUTE_NAME' is accepted"
        else
            echo "   ⚠️  HTTPRoute '$HTTPROUTE_NAME' status pending"
        fi
        kubectl get httproute $HTTPROUTE_NAME -n $APP_NAMESPACE
    else
        echo "   ⚠️  No HTTPRoute found"
    fi
else
    echo "   ⚠️  HTTPRoute resources not found"
fi

# Check application deployment
echo ""
echo "📋 Checking application deployment..."
if kubectl get deployment $APP_NAME -n $APP_NAMESPACE >/dev/null 2>&1; then
    APP_READY=$(kubectl get deployment $APP_NAME -n $APP_NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    APP_DESIRED=$(kubectl get deployment $APP_NAME -n $APP_NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [ "$APP_READY" = "$APP_DESIRED" ] && [ "$APP_READY" -gt 0 ]; then
        echo "   ✅ Application is ready ($APP_READY/$APP_DESIRED pods)"
    else
        echo "   ⚠️  Application not fully ready ($APP_READY/$APP_DESIRED pods)"
    fi
else
    echo "   ⚠️  Application deployment not found"
fi

# Display access instructions
echo ""
echo "=========================================="
echo "  Access Instructions"
echo "=========================================="
echo ""

if [ "$TRAEFIK_SVC_TYPE" = "LoadBalancer" ] && [ -n "$TRAEFIK_LB_IP" ]; then
    echo "✅ Using LoadBalancer IP: $TRAEFIK_LB_IP"
    echo ""
    echo "1. Add hostname to /etc/hosts (one-time setup):"
    echo "   echo \"$TRAEFIK_LB_IP dm-nkp-gitops-custom-app.local\" | sudo tee -a /etc/hosts"
    echo ""
    echo "2. Access application paths:"
    echo ""
    echo "   Main Application:"
    echo "   curl http://dm-nkp-gitops-custom-app.local/"
    echo "   curl http://dm-nkp-gitops-custom-app.local/health"
    echo "   curl http://dm-nkp-gitops-custom-app.local/ready"
    echo ""
    echo "   Or directly via LoadBalancer IP:"
    echo "   curl -H \"Host: dm-nkp-gitops-custom-app.local\" http://$TRAEFIK_LB_IP/"
    echo "   curl -H \"Host: dm-nkp-gitops-custom-app.local\" http://$TRAEFIK_LB_IP/health"
    echo ""
    echo "3. Verify HTTPRoute is working:"
    echo "   kubectl get httproute -n $APP_NAMESPACE"
    echo "   kubectl describe httproute -n $APP_NAMESPACE"
    echo ""

    # Test access
    echo "4. Testing access..."
    if curl -s -H "Host: dm-nkp-gitops-custom-app.local" "http://$TRAEFIK_LB_IP/" >/dev/null 2>&1; then
        echo "   ✅ Application is accessible via LoadBalancer IP"
        RESPONSE=$(curl -s -H "Host: dm-nkp-gitops-custom-app.local" "http://$TRAEFIK_LB_IP/" 2>/dev/null || echo "")
        if [ -n "$RESPONSE" ]; then
            echo "   Response preview: $(echo "$RESPONSE" | head -c 100)..."
        fi
    else
        echo "   ⚠️  Could not access application (check HTTPRoute and Gateway status)"
    fi

elif [ "$TRAEFIK_SVC_TYPE" = "LoadBalancer" ]; then
    echo "⚠️  LoadBalancer type but IP not assigned yet"
    echo ""
    echo "   Wait for IP assignment:"
    echo "   watch kubectl get svc traefik -n $TRAEFIK_NAMESPACE"
    echo ""
    echo "   Or use port-forward in the meantime:"
    echo "   kubectl port-forward -n $TRAEFIK_NAMESPACE svc/traefik 8080:80"
    echo ""

elif [ "$TRAEFIK_SVC_TYPE" = "NodePort" ] && [ -n "$TRAEFIK_NODEPORT" ]; then
    NODE_IP=$(docker inspect ${CLUSTER_NAME}-control-plane --format='{{.NetworkSettings.Networks.kind.IPAddress}}' 2>/dev/null || echo "localhost")
    echo "⚠️  Using NodePort (MetalLB not configured or failed)"
    echo ""
    echo "   Access via NodePort:"
    echo "   curl -H \"Host: dm-nkp-gitops-custom-app.local\" http://${NODE_IP}:${TRAEFIK_NODEPORT}/"
    echo ""
    echo "   Or use port-forward:"
    echo "   kubectl port-forward -n $TRAEFIK_NAMESPACE svc/traefik 8080:80"
    echo ""
else
    echo "⚠️  Traefik service not properly configured"
    echo ""
    echo "   Check service status:"
    echo "   kubectl get svc traefik -n $TRAEFIK_NAMESPACE"
    echo ""
fi

echo "=========================================="
echo ""
echo "📚 Additional Commands:"
echo ""
echo "   Check Traefik service:"
echo "   kubectl get svc traefik -n $TRAEFIK_NAMESPACE"
echo ""
echo "   Check HTTPRoute:"
echo "   kubectl get httproute -n $APP_NAMESPACE"
echo "   kubectl describe httproute -n $APP_NAMESPACE"
echo ""
echo "   Check Gateway:"
echo "   kubectl get gateway -n $TRAEFIK_NAMESPACE"
echo ""
echo "   Check MetalLB:"
echo "   kubectl get pods -n metallb-system"
echo "   kubectl get ipaddresspool -n metallb-system"
echo ""
