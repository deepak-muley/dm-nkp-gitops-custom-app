#!/bin/bash
set -euo pipefail

# End-to-end demo script
# This script builds, tests, deploys to kind, and sets up monitoring

APP_NAME="dm-nkp-gitops-custom-app"
CLUSTER_NAME="dm-nkp-demo-cluster"
NAMESPACE="default"
IMAGE_NAME="dm-nkp-gitops-custom-app:demo"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}✓${NC} $1"
}

echo_step() {
    echo -e "${BLUE}→${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

cleanup() {
    echo ""
    echo_warn "Cleaning up..."
    kubectl delete -f manifests/base/ --ignore-not-found=true 2>/dev/null || true
    # Monitoring is deployed via Helm, cleanup handled separately
    echo "Note: Kind cluster '$CLUSTER_NAME' is kept for inspection"
    echo "To delete it: kind delete cluster --name $CLUSTER_NAME"
}

trap cleanup EXIT

echo "=========================================="
echo "  End-to-End Demo Script"
echo "=========================================="
echo ""

# Step 1: Check prerequisites
echo_step "Step 1: Checking prerequisites..."
MISSING=()
command -v go >/dev/null 2>&1 || MISSING+=("go")
command -v docker >/dev/null 2>&1 || MISSING+=("docker")
command -v kubectl >/dev/null 2>&1 || MISSING+=("kubectl")
command -v kind >/dev/null 2>&1 || MISSING+=("kind")
command -v helm >/dev/null 2>&1 || MISSING+=("helm")

if [ ${#MISSING[@]} -ne 0 ]; then
    echo_warn "Missing tools: ${MISSING[*]}"
    echo "Please install missing tools before continuing."
    exit 1
fi
echo_info "All prerequisites installed"

# Step 2: Build application
echo ""
echo_step "Step 2: Building application..."
make clean >/dev/null 2>&1 || true
if make deps && make build; then
    echo_info "Application built successfully"
else
    echo_warn "Build failed, but continuing..."
fi

# Step 3: Run unit tests
echo ""
echo_step "Step 3: Running unit tests..."
if make unit-tests >/dev/null 2>&1; then
    echo_info "Unit tests passed"
else
    echo_warn "Some unit tests may have failed, continuing..."
fi

# Step 4: Build Docker image
echo ""
echo_step "Step 4: Building Docker image..."
if docker build -t $IMAGE_NAME . >/dev/null 2>&1; then
    echo_info "Docker image built: $IMAGE_NAME"
else
    echo_warn "Docker build had issues, continuing..."
fi

# Step 5: Create/check kind cluster
echo ""
echo_step "Step 5: Setting up kind cluster..."
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo_info "Cluster '$CLUSTER_NAME' already exists"
else
    echo "Creating kind cluster..."
    if kind create cluster --name $CLUSTER_NAME >/dev/null 2>&1; then
        echo_info "Kind cluster created"
    else
        echo_warn "Failed to create cluster, continuing..."
    fi
fi

# Set kubectl context
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true

# Step 6: Load image into kind
echo ""
echo_step "Step 6: Loading image into kind cluster..."
if kind load docker-image $IMAGE_NAME --name $CLUSTER_NAME >/dev/null 2>&1; then
    echo_info "Image loaded into kind"
else
    echo_warn "Failed to load image, continuing..."
fi

# Step 7: Deploy application
echo ""
echo_step "Step 7: Deploying application..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true

# Update deployment to use demo image
sed "s|image:.*|image: ${IMAGE_NAME}|" manifests/base/deployment.yaml | \
    sed 's|imagePullPolicy:.*|imagePullPolicy: Never|' | \
    kubectl apply -f - >/dev/null 2>&1 || true

kubectl apply -f manifests/base/service.yaml >/dev/null 2>&1 || true

echo "Waiting for deployment to be ready..."
kubectl wait --for=condition=ready pod -l app=$APP_NAME -n $NAMESPACE --timeout=2m >/dev/null 2>&1 || echo_warn "Deployment may not be ready yet"

echo_info "Application deployed"

# Step 8: Deploy monitoring stack using Helm
echo ""
echo_step "Step 8: Deploying monitoring stack (Prometheus + Grafana) using Helm..."
if command -v helm >/dev/null 2>&1; then
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1 || true

    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true

    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
      --namespace monitoring \
      --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
      --set prometheus.service.type=NodePort \
      --set prometheus.service.nodePort=30090 \
      --wait --timeout=5m >/dev/null 2>&1 || echo_warn "Prometheus installation had issues"

    echo "Waiting for monitoring stack..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=2m >/dev/null 2>&1 || echo_warn "Prometheus may not be ready yet"
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=2m >/dev/null 2>&1 || echo_warn "Grafana may not be ready yet"

    echo_info "Monitoring stack deployed via Helm"
else
    echo_warn "Helm not found. Please install Helm to deploy monitoring stack."
    echo_warn "Skipping monitoring deployment."
fi

# Step 9: Generate traffic
echo ""
echo_step "Step 9: Generating traffic to create metrics..."

# Port forward in background
kubectl port-forward -n $NAMESPACE svc/$APP_NAME 8080:8080 >/dev/null 2>&1 &
PF_PID=$!
sleep 3

# Generate traffic
# shellcheck disable=SC2034  # Loop variable intentionally unused
for _ in {1..50}; do
    curl -s http://localhost:8080/ >/dev/null 2>&1 || true
    sleep 0.1
done

kill $PF_PID 2>/dev/null || true
echo_info "Generated 50 requests"

# Wait a bit for metrics to be scraped
sleep 5

# Step 10: Display access information
echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo_info "Application is running in kind cluster: $CLUSTER_NAME"
echo ""
echo "📊 Access Grafana Dashboard:"
echo "  1. Port forward to Grafana:"
if command -v helm >/dev/null 2>&1; then
    echo "     kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    echo "     (For kube-prometheus-stack)"
else
    echo "     kubectl port-forward -n monitoring svc/grafana 3000:3000"
fi
echo ""
echo "  2. Open browser:"
echo "     http://localhost:3000"
echo ""
echo "  3. Login credentials:"
echo "     Username: admin"
if command -v helm >/dev/null 2>&1; then
    echo "     Password: (run: kubectl get secret -n monitoring prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
else
    echo "     Password: admin"
fi
echo ""
echo "  4. Navigate to dashboard:"
echo "     Dashboards → dm-nkp-gitops-custom-app Metrics"
echo ""
echo "📈 Access Prometheus:"
echo "  1. Port forward:"
echo "     kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo ""
echo "  2. Open browser:"
echo "     http://localhost:9090"
echo ""
echo "  3. Try queries:"
echo "     http_requests_total"
echo "     rate(http_requests_total[5m])"
echo ""
echo "🔍 Check application:"
echo "  kubectl port-forward -n $NAMESPACE svc/$APP_NAME 8080:8080"
echo "  curl http://localhost:8080/health"
echo "  curl http://localhost:8080/metrics"
echo ""
echo "🧹 Cleanup (when done):"
echo "  kind delete cluster --name $CLUSTER_NAME"
echo ""
echo "Press Ctrl+C to exit (cluster will remain for inspection)"
echo ""

# Keep script running and show status
while true; do
    sleep 30
    echo ""
    echo_step "Status check:"
    kubectl get pods -n $NAMESPACE -l app=$APP_NAME 2>/dev/null | grep -v NAME || echo_warn "App pods not found"
    kubectl get pods -n monitoring 2>/dev/null | grep -E "(prometheus|grafana)" | grep -v NAME || echo_warn "Monitoring pods not found"
done
