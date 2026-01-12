#!/bin/bash
set -euo pipefail

# End-to-End Demo Script with OpenTelemetry Observability Stack
# This script builds, tests, deploys to kind with full observability stack (OTel Collector, Prometheus, Loki, Tempo, Grafana)

APP_NAME="dm-nkp-gitops-custom-app"
CLUSTER_NAME="dm-nkp-demo-cluster"
APP_NAMESPACE="default"
OBSERVABILITY_NAMESPACE="observability"
IMAGE_NAME="dm-nkp-gitops-custom-app:demo"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
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

echo_error() {
    echo -e "${RED}✗${NC} $1"
}

cleanup() {
    echo ""
    echo_warn "Cleaning up..."
    # Note: We keep the cluster running for inspection
    # To fully cleanup: kind delete cluster --name $CLUSTER_NAME
    echo "Note: Kind cluster '$CLUSTER_NAME' is kept for inspection"
    echo "To delete it: kind delete cluster --name $CLUSTER_NAME"
}

trap cleanup EXIT

echo "=========================================="
echo "  End-to-End Demo with OpenTelemetry"
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
    echo_error "Missing tools: ${MISSING[*]}"
    echo "Please install missing tools before continuing."
    exit 1
fi
echo_info "All prerequisites installed"

# Step 2: Build application (only if Go files changed)
echo ""
echo_step "Step 2: Building application..."
# Check if Go files have changed
CHANGED_GO_FILES=$(git diff --name-only --diff-filter=ACMRTUXB HEAD -- "*.go" 2>/dev/null || echo "")
UNTRACKED_GO_FILES=$(git ls-files --others --exclude-standard "*.go" 2>/dev/null || echo "")

if [ -z "$CHANGED_GO_FILES" ] && [ -z "$UNTRACKED_GO_FILES" ]; then
    echo_info "No Go files changed. Skipping build and tests."
    SKIP_BUILD=true
else
    SKIP_BUILD=false
    if [ -n "$CHANGED_GO_FILES" ]; then
        echo "Go files changed. Changed files:"
        echo "$CHANGED_GO_FILES" | sed "s/^/  - /"
    fi
    if [ -n "$UNTRACKED_GO_FILES" ]; then
        echo "Untracked Go files detected:"
        echo "$UNTRACKED_GO_FILES" | sed "s/^/  - /"
    fi
    
    make clean >/dev/null 2>&1 || true
    if make deps && make build; then
        echo_info "Application built successfully"
    else
        echo_warn "Build failed, but continuing..."
    fi
fi

# Step 3: Run unit tests (only if Go files changed)
echo ""
echo_step "Step 3: Running unit tests..."
if [ "$SKIP_BUILD" = "true" ]; then
    echo_info "No Go files changed. Skipping unit tests."
else
    if make unit-tests >/dev/null 2>&1; then
        echo_info "Unit tests passed"
    else
        echo_warn "Some unit tests may have failed, continuing..."
    fi
fi

# Step 4: Build Docker image (only if Go files changed)
echo ""
echo_step "Step 4: Building Docker image..."
if [ "$SKIP_BUILD" = "true" ]; then
    echo_info "No Go files changed. Skipping Docker image build."
    echo "Using existing image: $IMAGE_NAME (if it exists)"
else
    # Use docker build (faster) for local development, pack build for production
    # For local/e2e testing, Dockerfile is much faster than pack build
    # Pack build is optimized for CI/CD and production builds
    if [ "${USE_PACK_BUILD:-}" = "1" ] || [ "${USE_PACK_BUILD:-}" = "true" ]; then
        # Use pack build with optimizations
        if command -v pack >/dev/null 2>&1; then
            echo "Using pack build (slower but more optimized for production)..."
            CACHE_IMAGE="${IMAGE_NAME}-cache"
            if pack build $IMAGE_NAME \
                --builder gcr.io/buildpacks/builder:google-22 \
                --pull-policy if-not-present \
                --cache-image $CACHE_IMAGE \
                --env GOOGLE_RUNTIME_VERSION=1.25.5 \
                --env GOOGLE_BUILDABLE=./cmd/app \
                --env PORT=8080 \
                --env METRICS_PORT=9090 >/dev/null 2>&1; then
                echo_info "Docker image built with pack: $IMAGE_NAME"
            else
                echo_warn "Pack build failed, trying docker build as fallback..."
                if docker build -t $IMAGE_NAME . >/dev/null 2>&1; then
                    echo_info "Docker image built (using docker build): $IMAGE_NAME"
                else
                    echo_warn "Docker build had issues, continuing..."
                fi
            fi
        else
            echo_warn "pack not found, using docker build..."
            if docker build -t $IMAGE_NAME . >/dev/null 2>&1; then
                echo_info "Docker image built: $IMAGE_NAME"
            else
                echo_warn "Docker build had issues, continuing..."
            fi
        fi
    else
        # Default: Use Dockerfile build (much faster for local development)
        echo "Using docker build (faster for local development)..."
        echo "Tip: Set USE_PACK_BUILD=1 to use pack build instead."
        if docker build -t $IMAGE_NAME . >/dev/null 2>&1; then
            echo_info "Docker image built: $IMAGE_NAME"
        else
            echo_warn "Docker build had issues, continuing..."
        fi
    fi
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
        echo_error "Failed to create cluster"
        exit 1
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
    echo_error "Failed to load image"
    exit 1
fi

# Step 7: Deploy observability stack (OTel Collector, Prometheus, Loki, Tempo, Grafana)
echo ""
echo_step "Step 7: Deploying OpenTelemetry observability stack..."
OTEL_DEPLOYED=false
if [ -f "scripts/setup-observability-stack.sh" ]; then
    echo "Using scripts/setup-observability-stack.sh..."
    if bash scripts/setup-observability-stack.sh; then
        echo_info "Observability stack deployed"
        OTEL_DEPLOYED=true
    else
        echo_warn "setup-observability-stack.sh failed, trying manual deployment..."
        OTEL_DEPLOYED=false
    fi
fi

# If setup script failed or doesn't exist, deploy manually
if [ "$OTEL_DEPLOYED" = "false" ]; then
    echo_warn "Deploying observability stack manually..."
    
    # Create namespace
    kubectl create namespace $OBSERVABILITY_NAMESPACE --dry-run=client -o yaml | kubectl apply -f - || true
    
    # Add Helm repos
    echo "Adding Helm repositories..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
    helm repo update || echo_warn "Helm repo update had issues, continuing..."
    
    # Install Prometheus + Grafana
    echo "Installing Prometheus and Grafana..."
    # Handle CRD version mismatch by automatically uninstalling and reinstalling if needed
    INSTALL_ERROR_FILE="/tmp/prometheus-install-$$.log"
    if helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
      --namespace $OBSERVABILITY_NAMESPACE \
      --create-namespace \
      --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
      --set prometheus.prometheusSpec.retention=1h \
      --set grafana.adminPassword=admin \
      --wait --timeout=5m 2>&1 | tee "$INSTALL_ERROR_FILE"; then
        echo_info "Prometheus and Grafana installed successfully"
        rm -f "$INSTALL_ERROR_FILE"
    else
        INSTALL_ERROR=$(cat "$INSTALL_ERROR_FILE" 2>/dev/null || echo "")
        if echo "$INSTALL_ERROR" | grep -q "field not declared in schema"; then
            echo_warn "Upgrade failed due to CRD schema mismatch (ServiceMonitor CRD version incompatibility)"
            echo_warn "Automatically uninstalling and reinstalling to fix CRD version mismatch..."
            helm uninstall prometheus -n $OBSERVABILITY_NAMESPACE 2>/dev/null || true
            sleep 5
            # Reinstall with fresh CRDs
            if helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
              --namespace $OBSERVABILITY_NAMESPACE \
              --create-namespace \
              --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
              --set prometheus.prometheusSpec.retention=1h \
              --set grafana.adminPassword=admin \
              --wait --timeout=5m; then
                echo_info "Prometheus reinstalled successfully after CRD fix"
            else
                echo_warn "Prometheus reinstallation had issues, continuing..."
            fi
        else
            echo_warn "Prometheus installation had issues: $(echo "$INSTALL_ERROR" | head -3)"
        fi
        rm -f "$INSTALL_ERROR_FILE"
    fi
    
    # Install Loki (using loki-simple-scalable for single-node kind clusters)
    echo "Installing Loki..."
    # Note: grafana/loki and loki-stack are deprecated
    # Using loki-simple-scalable for local/testing clusters (simpler, single binary, no anti-affinity)
    # For production multi-node clusters, consider loki-distributed instead
    if helm upgrade --install loki grafana/loki-simple-scalable \
      --namespace $OBSERVABILITY_NAMESPACE \
      --set singleBinary.replicas=1 \
      --wait --timeout=5m; then
        echo_info "Loki installed successfully (using loki-simple-scalable)"
    else
        echo_warn "Loki-simple-scalable installation had issues, trying loki-distributed with anti-affinity disabled..."
        # Fallback: try loki-distributed with anti-affinity disabled for single-node clusters
        if helm upgrade --install loki grafana/loki-distributed \
          --namespace $OBSERVABILITY_NAMESPACE \
          --set loki.read.replicas=1 \
          --set loki.write.replicas=1 \
          --set loki.read.affinity='' \
          --set loki.write.affinity='' \
          --set loki.backend.affinity='' \
          --wait --timeout=5m; then
            echo_info "Loki installed successfully (using loki-distributed with anti-affinity disabled)"
        else
            echo_warn "Loki installation failed, continuing..."
        fi
    fi
    
    # Install Tempo
    echo "Installing Tempo..."
    if helm upgrade --install tempo grafana/tempo \
      --namespace $OBSERVABILITY_NAMESPACE \
      --set serviceAccount.create=true \
      --wait --timeout=5m; then
        echo_info "Tempo installed successfully"
    else
        echo_warn "Tempo installation had issues, continuing..."
    fi
    
    # Install cert-manager (required by OTel Operator for webhook certificates)
    echo "Installing cert-manager (required by OTel Operator)..."
    helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
    helm repo update || true
    
    if helm list -n cert-manager 2>/dev/null | grep -q cert-manager; then
        echo_info "cert-manager already installed"
    else
        echo "Installing cert-manager..."
        if helm upgrade --install cert-manager jetstack/cert-manager \
          --namespace cert-manager \
          --create-namespace \
          --set installCRDs=true \
          --wait --timeout=5m; then
            echo_info "cert-manager installed successfully"
            # Wait for cert-manager webhook to be ready
            echo "Waiting for cert-manager webhook to be ready..."
            kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=3m 2>/dev/null || echo_warn "cert-manager webhook may not be ready yet"
        else
            echo_warn "cert-manager installation failed"
            echo_warn "OTel Operator requires cert-manager. Please install manually:"
            echo_warn "  helm repo add jetstack https://charts.jetstack.io"
            echo_warn "  helm repo update"
            echo_warn "  helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set installCRDs=true"
        fi
    fi
    
    # Install OTel Operator using Helm chart (preferred approach for platform)
    echo "Installing OTel Operator using Helm chart..."
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
    helm repo update || true
    
    echo "Checking if OTel Operator is already installed..."
    if helm list -n opentelemetry-operator-system 2>/dev/null | grep -q opentelemetry-operator; then
        echo_info "OTel Operator Helm release already exists, checking if operator is running..."
        if kubectl get pods -n opentelemetry-operator-system -l app.kubernetes.io/name=opentelemetry-operator 2>/dev/null | grep -q Running; then
            echo_info "OTel Operator is already installed and running"
            OTEL_DEPLOYED=true
        else
            echo_warn "OTel Operator Helm release exists but operator pods are not running"
            echo "Upgrading OTel Operator..."
            if helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
              --namespace opentelemetry-operator-system \
              --create-namespace \
              --set manager.collectorImage.repository=otel/opentelemetry-collector-contrib \
              --wait --timeout=5m; then
                echo_info "OTel Operator upgraded successfully"
                OTEL_DEPLOYED=true
            else
                echo_error "OTel Operator upgrade failed"
                OTEL_DEPLOYED=false
            fi
        fi
    else
        echo "Installing OTel Operator via Helm..."
        if helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
          --namespace opentelemetry-operator-system \
          --create-namespace \
          --set manager.collectorImage.repository=otel/opentelemetry-collector-contrib \
          --wait --timeout=5m; then
            echo_info "OTel Operator installed successfully via Helm"
            OTEL_DEPLOYED=true
        else
            echo_error "OTel Operator installation failed"
            echo_warn "OTel Operator is required for metrics and traces. Please install manually."
            OTEL_DEPLOYED=false
        fi
    fi
    
    # Wait for OTel Operator to be ready
    if [ "$OTEL_DEPLOYED" = "true" ]; then
        echo "Waiting for OTel Operator to be ready..."
        set +e  # Temporarily disable exit on error
        if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=opentelemetry-operator -n opentelemetry-operator-system --timeout=3m 2>/dev/null; then
            echo_info "OTel Operator is ready"
        else
            echo_warn "OTel Operator may not be fully ready yet, continuing..."
        fi
        set -e  # Re-enable exit on error
        
        # Create OpenTelemetryCollector instance if it doesn't exist
        echo "Checking for OpenTelemetryCollector instance..."
        if kubectl get opentelemetrycollector -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -v NAME | grep -q .; then
            echo_info "OpenTelemetryCollector instance already exists"
            kubectl get opentelemetrycollector -n $OBSERVABILITY_NAMESPACE 2>/dev/null
        else
            echo "Creating OpenTelemetryCollector instance..."
            cat <<EOF | kubectl apply -f -
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: ${OBSERVABILITY_NAMESPACE}
spec:
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      batch:
      resource:
        attributes:
          - key: service.name
            value: otel-collector
            action: upsert
    exporters:
      prometheusremotewrite:
        endpoint: http://prometheus-kube-prometheus-prometheus.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:9090/api/v1/write
      logging:
        loglevel: info
      otlp/tempo:
        endpoint: tempo.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:4317
        tls:
          insecure: true
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [otlp/tempo]
        metrics:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [prometheusremotewrite]
        logs:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [logging]
  mode: deployment
  replicas: 1
EOF
            if [ $? -eq 0 ]; then
                echo_info "OpenTelemetryCollector instance created successfully"
                echo "Waiting for OpenTelemetryCollector to be ready..."
                sleep 5
            else
                echo_warn "Failed to create OpenTelemetryCollector instance, you may need to create it manually"
            fi
        fi
    fi
fi

# Wait for observability stack to be ready
echo "Waiting for observability stack..."
# Ensure namespace exists
kubectl get namespace $OBSERVABILITY_NAMESPACE >/dev/null 2>&1 || {
    echo_warn "Observability namespace does not exist. Creating it..."
    kubectl create namespace $OBSERVABILITY_NAMESPACE || true
}

# Give it a moment for resources to start appearing
sleep 5

# Try multiple label selectors for OTel Collector (local chart vs upstream chart)
OTEL_READY=false
set +e  # Temporarily disable exit on error for wait checks
OTEL_POD_NAME=$(kubectl get pods -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.items[?(@.metadata.name=~"otel.*collector.*")].metadata.name}' 2>/dev/null | cut -d' ' -f1 || echo "")
if [ -n "$OTEL_POD_NAME" ]; then
    if kubectl wait --for=condition=ready pod "$OTEL_POD_NAME" -n $OBSERVABILITY_NAMESPACE --timeout=2m >/dev/null 2>&1; then
        echo_info "OTel Collector is ready: $OTEL_POD_NAME"
        OTEL_READY=true
    fi
fi

if [ "$OTEL_READY" = "false" ]; then
    # Try label-based selectors
    if kubectl wait --for=condition=ready pod -l component=otel-collector -n $OBSERVABILITY_NAMESPACE --timeout=1m >/dev/null 2>&1; then
        echo_info "OTel Collector is ready (component=otel-collector)"
        OTEL_READY=true
    elif kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=opentelemetry-collector -n $OBSERVABILITY_NAMESPACE --timeout=1m >/dev/null 2>&1; then
        echo_info "OTel Collector is ready (app.kubernetes.io/name=opentelemetry-collector)"
        OTEL_READY=true
    else
        echo_warn "OTel Collector may not be ready yet. Checking status..."
        kubectl get pods -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -i otel || echo_warn "No OTel Collector pods found"
        kubectl get deployment -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -i otel || echo_warn "No OTel Collector deployment found"
        echo_warn "OTel Collector is not ready, but continuing. Telemetry export may fail until it's ready."
    fi
fi

if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n $OBSERVABILITY_NAMESPACE --timeout=2m >/dev/null 2>&1; then
    echo_info "Prometheus is ready"
else
    echo_warn "Prometheus may not be ready yet"
fi

if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n $OBSERVABILITY_NAMESPACE --timeout=2m >/dev/null 2>&1; then
    echo_info "Grafana is ready"
else
    echo_warn "Grafana may not be ready yet"
fi

# Verify OTel Collector or Operator deployment
echo ""
echo_step "Verifying OTel deployment..."
OTEL_VERIFIED=false
OTEL_TYPE=""

# Check if OTel Operator is installed (uses OpenTelemetryCollector CRD)
if kubectl get crd opentelemetrycollectors.opentelemetry.io >/dev/null 2>&1; then
    echo_info "OTel Operator detected (OpenTelemetryCollector CRD exists)"
    OTEL_TYPE="operator"
    # Check if OTel Operator is running (in opentelemetry-operator-system namespace)
    if kubectl get pods -n opentelemetry-operator-system -l app.kubernetes.io/name=opentelemetry-operator 2>/dev/null | grep -q Running; then
        echo_info "OTel Operator pods are running"
        kubectl get pods -n opentelemetry-operator-system -l app.kubernetes.io/name=opentelemetry-operator 2>/dev/null | grep Running || true
        # Check if OpenTelemetryCollector instance exists
        if kubectl get opentelemetrycollector -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -v NAME | grep -q .; then
            echo_info "OpenTelemetryCollector instance(s) found"
            kubectl get opentelemetrycollector -n $OBSERVABILITY_NAMESPACE 2>/dev/null
            # Check if collector pods are running (managed by operator)
            if kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep -q Running; then
                echo_info "OpenTelemetryCollector pods are running (managed by operator)"
                kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep Running || true
                OTEL_VERIFIED=true
            else
                echo_warn "OpenTelemetryCollector CR exists but pods are not running yet"
            fi
        else
            echo_warn "OTel Operator is installed but no OpenTelemetryCollector instance found"
            echo_warn "You need to create an OpenTelemetryCollector custom resource"
        fi
    else
        echo_warn "OTel Operator CRD exists but operator pods are not running"
    fi
fi

# Note: We only check for OTel Operator now (not direct Collector Helm chart)
# OTel Collector instances are managed by the Operator via OpenTelemetryCollector CR
# Check if OpenTelemetryCollector pods are running (created by operator)
if [ "$OTEL_VERIFIED" = "false" ]; then
    if kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep -q Running; then
        echo_info "OpenTelemetryCollector pods are running (managed by operator)"
        kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep Running || true
        OTEL_VERIFIED=true
    fi
fi

# Final check: Look for any OTel-related pods/services
if [ "$OTEL_VERIFIED" = "false" ]; then
    echo ""
    echo_error "OTel Collector/Operator not found or not ready!"
    echo_warn "This will cause issues with telemetry export (metrics and traces will not work)."
    echo_warn "The application will still run, but metrics/traces export will fail."
    echo ""
    echo "Checking for any OTel-related resources..."
    kubectl get pods -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -iE "otel|opentelemetry" || echo_warn "  No OTel pods found"
    kubectl get svc -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -iE "otel|opentelemetry" || echo_warn "  No OTel services found"
    kubectl get deployment -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -iE "otel|opentelemetry" || echo_warn "  No OTel deployments found"
    kubectl get statefulset -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -iE "otel|opentelemetry" || echo_warn "  No OTel statefulsets found"
fi

set -e  # Re-enable exit on error

if [ "$OTEL_VERIFIED" = "false" ]; then
    echo ""
    echo_warn "⚠️  WARNING: OTel Collector/Operator is not deployed or not ready"
    echo_warn "   Metrics and traces will not work until OTel Collector is deployed."
    echo_warn "   Deployment options:"
    echo_warn ""
    echo_warn "   Deploy cert-manager first (required by OTel Operator):"
    echo_warn "     helm repo add jetstack https://charts.jetstack.io"
    echo_warn "     helm repo update"
    echo_warn "     helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set installCRDs=true"
    echo_warn "   Deploy OTel Operator (Helm chart - recommended):"
    echo_warn "     helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts"
    echo_warn "     helm repo update"
    echo_warn "     helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \\"
    echo_warn "       --namespace opentelemetry-operator-system --create-namespace"
    echo_warn "     # Then create an OpenTelemetryCollector custom resource"
    echo_warn ""
    echo_warn "   Continuing with deployment, but telemetry export will fail..."
fi

echo_info "Observability stack deployment completed. Proceeding to Gateway API deployment..."

# Step 8: Deploy Gateway API + Traefik with Gateway API support
echo ""
echo_step "Step 8: Deploying Gateway API + Traefik..."

TRAEFIK_NAMESPACE="traefik-system"

# Check if Gateway API is already installed
if kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1; then
    echo_info "Gateway API CRDs already installed"
else
    echo "Installing Gateway API CRDs..."
    set +e  # Temporarily disable exit on error
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml >/dev/null 2>&1 || {
        echo_warn "Failed to install Gateway API CRDs, continuing..."
    }
    set -e  # Re-enable exit on error
    
    # Wait for CRDs to be established
    echo "Waiting for Gateway API CRDs..."
    set +e  # Temporarily disable exit on error
    kubectl wait --for condition=established --timeout=60s crd/gateways.gateway.networking.k8s.io >/dev/null 2>&1 || echo_warn "Gateway API CRDs may not be ready yet"
    set -e  # Re-enable exit on error
    echo_info "Gateway API CRDs installed"
fi

# Install Traefik with Gateway API support using Helm
echo ""
echo "Installing Traefik with Gateway API support using Helm..."
set +e  # Temporarily disable exit on error

# Add Helm repo if not already added
if ! helm repo list 2>/dev/null | grep -q traefik; then
    helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1 || true
fi

# Create namespace
kubectl create namespace $TRAEFIK_NAMESPACE --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true

# Install Traefik with Gateway API support
if helm upgrade --install traefik traefik/traefik \
  --namespace $TRAEFIK_NAMESPACE \
  --set experimental.kubernetesGateway.enabled=true \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443 \
  --set service.type=NodePort \
  --wait --timeout=5m >/dev/null 2>&1; then
    echo_info "Traefik with Gateway API support installed successfully"
else
    echo_warn "Traefik installation had issues, continuing..."
fi

set -e  # Re-enable exit on error

# Wait for Traefik to be ready
echo "Waiting for Traefik to be ready..."
set +e  # Temporarily disable exit on error
if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n $TRAEFIK_NAMESPACE --timeout=3m >/dev/null 2>&1; then
    echo_info "Traefik is ready"
else
    echo_warn "Traefik may not be ready yet, continuing..."
fi
set -e  # Re-enable exit on error

# Create Gateway resource (required for HTTPRoute to work)
# Traefik with Gateway API support automatically creates a GatewayClass
# We need to find the GatewayClass name and create a Gateway referencing it
echo ""
echo "Creating Gateway resource..."
set +e  # Temporarily disable exit on error

# Wait a moment for Traefik to create the GatewayClass
sleep 5

# Find the GatewayClass created by Traefik
GATEWAY_CLASS_NAME=$(kubectl get gatewayclass -o jsonpath='{.items[?(@.spec.controllerName=="traefik.io/gateway-controller")].metadata.name}' 2>/dev/null | head -1)
if [ -z "$GATEWAY_CLASS_NAME" ]; then
    # Try alternative controller name format
    GATEWAY_CLASS_NAME=$(kubectl get gatewayclass -o jsonpath='{.items[?(@.spec.controllerName=="traefik.io/ingress-controller")].metadata.name}' 2>/dev/null | head -1)
fi
if [ -z "$GATEWAY_CLASS_NAME" ]; then
    # Try any GatewayClass that exists
    GATEWAY_CLASS_NAME=$(kubectl get gatewayclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
fi

if [ -z "$GATEWAY_CLASS_NAME" ]; then
    # Create a default GatewayClass if none exists
    echo_warn "No GatewayClass found, creating default one..."
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1 || true
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: traefik
spec:
  controllerName: traefik.io/gateway-controller
EOF
    GATEWAY_CLASS_NAME="traefik"
    sleep 2
fi

if [ -n "$GATEWAY_CLASS_NAME" ]; then
    echo_info "Using GatewayClass: $GATEWAY_CLASS_NAME"
    # Create Gateway resource
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1 || true
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: traefik
  namespace: ${TRAEFIK_NAMESPACE}
spec:
  gatewayClassName: ${GATEWAY_CLASS_NAME}
  listeners:
    - name: web
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
EOF

    if kubectl get gateway traefik -n $TRAEFIK_NAMESPACE >/dev/null 2>&1; then
        echo_info "Gateway resource created: traefik in namespace ${TRAEFIK_NAMESPACE}"
        # Wait for Gateway to be accepted
        for i in {1..30}; do
            if kubectl get gateway traefik -n $TRAEFIK_NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null | grep -q True; then
                echo_info "Gateway accepted and ready"
                break
            fi
            sleep 2
        done
    else
        echo_warn "Gateway resource may not have been created, but continuing..."
    fi
else
    echo_warn "Could not determine GatewayClass name, Gateway may not work correctly"
fi

set -e  # Re-enable exit on error

echo_info "Gateway API + Traefik deployment completed"

# Small delay to ensure Gateway API CRDs are fully ready
sleep 3

# Step 9: Deploy application with OpenTelemetry configuration
echo ""
echo_step "Step 9: Deploying application with OpenTelemetry..."
echo "Starting application deployment..."
echo "Creating namespace $APP_NAMESPACE if it doesn't exist..."
kubectl create namespace $APP_NAMESPACE --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true

# Extract repository and tag from IMAGE_NAME (format: "repo:tag" or just "repo")
IMAGE_REPO=$(echo $IMAGE_NAME | cut -d':' -f1)
IMAGE_TAG=$(echo $IMAGE_NAME | cut -d':' -f2)
if [ "$IMAGE_TAG" = "$IMAGE_NAME" ]; then
    # No tag specified, use "demo" as default
    IMAGE_TAG="demo"
fi

# Check if Gateway API is available (for HTTPRoute deployment)
# Since we just deployed it in Step 8, it should be available
ENABLE_GATEWAY=false
set +e  # Temporarily disable exit on error for CRD check
if kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1; then
    ENABLE_GATEWAY=true
    echo_info "Gateway API detected - HTTPRoute will be enabled in Helm deployment"
else
    echo_warn "Gateway API CRD not found, but we just deployed it. Retrying..."
    sleep 2
    if kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1; then
        ENABLE_GATEWAY=true
        echo_info "Gateway API detected on retry - HTTPRoute will be enabled in Helm deployment"
    else
        echo_warn "Gateway API CRD still not found. HTTPRoute may not be enabled."
    fi
fi
set -e  # Re-enable exit on error

# Clean up any existing resources that might conflict with Helm
echo "Cleaning up any existing resources that might conflict..."
set +e  # Temporarily disable exit on error for cleanup

# Check if Helm release exists and uninstall it first (this handles Helm-managed resources)
if helm list -n $APP_NAMESPACE 2>/dev/null | grep -q "^${APP_NAME}[[:space:]]"; then
    echo_warn "Existing Helm release found, uninstalling it first..."
    helm uninstall $APP_NAME -n $APP_NAMESPACE >/dev/null 2>&1 || true
    sleep 3
fi

# Delete any existing resources that might have been created manually or from previous failed deployments
# In local testing, it's safe to delete and recreate - these might not have Helm labels/annotations
echo "Checking for existing resources that might conflict..."

# Delete Service (Helm can't adopt resources without proper labels/annotations)
if kubectl get svc $APP_NAME -n $APP_NAMESPACE >/dev/null 2>&1; then
    MANAGED_BY=$(kubectl get svc $APP_NAME -n $APP_NAMESPACE -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || echo "")
    # If not managed by Helm (empty or not "Helm"), delete it
    if [ -z "$MANAGED_BY" ] || [ "$MANAGED_BY" != "Helm" ]; then
        echo_warn "Found Service without Helm labels/annotations, deleting it..."
        kubectl delete svc $APP_NAME -n $APP_NAMESPACE --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
    fi
fi

# Delete Deployment
if kubectl get deployment $APP_NAME -n $APP_NAMESPACE >/dev/null 2>&1; then
    MANAGED_BY=$(kubectl get deployment $APP_NAME -n $APP_NAMESPACE -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || echo "")
    # If not managed by Helm (empty or not "Helm"), delete it
    if [ -z "$MANAGED_BY" ] || [ "$MANAGED_BY" != "Helm" ]; then
        echo_warn "Found Deployment without Helm labels/annotations, deleting it..."
        kubectl delete deployment $APP_NAME -n $APP_NAMESPACE --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
    fi
fi

# Delete other resources that might conflict
# ServiceAccount
if kubectl get serviceaccount $APP_NAME -n $APP_NAMESPACE >/dev/null 2>&1; then
    MANAGED_BY=$(kubectl get serviceaccount $APP_NAME -n $APP_NAMESPACE -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || echo "")
    if [ -z "$MANAGED_BY" ] || [ "$MANAGED_BY" != "Helm" ]; then
        echo_warn "Found ServiceAccount without Helm labels, deleting it..."
        kubectl delete serviceaccount $APP_NAME -n $APP_NAMESPACE --ignore-not-found=true >/dev/null 2>&1 || true
    fi
fi

# Check for HTTPRoute (if Gateway API is enabled) - only delete if not managed by Helm
if [ "$ENABLE_GATEWAY" = "true" ]; then
    HTTPROUTE_NAME=$(kubectl get httproute -n $APP_NAMESPACE -o jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io/name=="'$APP_NAME'")].metadata.name}' 2>/dev/null || echo "")
    if [ -z "$HTTPROUTE_NAME" ]; then
        # Try finding by name directly
        HTTPROUTE_NAME=$(kubectl get httproute -n $APP_NAMESPACE -o jsonpath='{.items[?(@.metadata.name=="'$APP_NAME'")].metadata.name}' 2>/dev/null || echo "")
    fi
    if [ -n "$HTTPROUTE_NAME" ]; then
        MANAGED_BY=$(kubectl get httproute $HTTPROUTE_NAME -n $APP_NAMESPACE -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || echo "")
        if [ -z "$MANAGED_BY" ] || [ "$MANAGED_BY" != "Helm" ]; then
            echo_warn "Found HTTPRoute without Helm labels, deleting it..."
            kubectl delete httproute $HTTPROUTE_NAME -n $APP_NAMESPACE --ignore-not-found=true >/dev/null 2>&1 || true
        fi
    fi
fi

# Wait a moment for resources to be fully deleted
echo "Waiting for cleanup to complete..."
sleep 3

# Verify resources are deleted
if kubectl get svc $APP_NAME -n $APP_NAMESPACE >/dev/null 2>&1; then
    echo_warn "Service still exists after cleanup, forcing deletion..."
    kubectl delete svc $APP_NAME -n $APP_NAMESPACE --ignore-not-found=true --grace-period=0 >/dev/null 2>&1 || true
fi

if kubectl get deployment $APP_NAME -n $APP_NAMESPACE >/dev/null 2>&1; then
    echo_warn "Deployment still exists after cleanup, forcing deletion..."
    kubectl delete deployment $APP_NAME -n $APP_NAMESPACE --ignore-not-found=true --grace-period=0 >/dev/null 2>&1 || true
    sleep 2
fi

set -e  # Re-enable exit on error

# Deploy using Helm chart with local testing values
if [ -f "chart/dm-nkp-gitops-custom-app/values-local-testing.yaml" ]; then
    echo "Deploying via Helm chart with local testing values..."
    echo "  Image: $IMAGE_REPO:$IMAGE_TAG"
    echo "  Namespace: $APP_NAMESPACE"
    
    # Build helm command with conditional gateway.enabled
    HELM_CMD="helm upgrade --install $APP_NAME chart/dm-nkp-gitops-custom-app \
      --namespace $APP_NAMESPACE \
      --create-namespace \
      -f chart/dm-nkp-gitops-custom-app/values-local-testing.yaml \
      --set image.repository=$IMAGE_REPO \
      --set image.tag=$IMAGE_TAG \
      --set image.pullPolicy=Never"
    
    # Enable Gateway API if detected
    if [ "$ENABLE_GATEWAY" = "true" ]; then
        HELM_CMD="$HELM_CMD --set gateway.enabled=true"
        echo "  Gateway API: enabled"
    else
        echo "  Gateway API: disabled (not detected)"
    fi
    
    HELM_CMD="$HELM_CMD --wait --timeout=5m"
    
    echo "Running Helm command..."
    echo "Command: $HELM_CMD"
    set +e  # Temporarily disable exit on error to handle Helm failures gracefully
    if eval $HELM_CMD 2>&1; then
        set -e  # Re-enable exit on error
        echo_info "Helm deployment successful"
    else
        HELM_EXIT_CODE=$?
        set -e  # Re-enable exit on error
        echo_warn "Helm deployment failed with exit code $HELM_EXIT_CODE, checking status..."
        helm status $APP_NAME --namespace $APP_NAMESPACE 2>&1 || true
        kubectl get pods -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME 2>&1 || true
        kubectl get pods -n $APP_NAMESPACE -l app=$APP_NAME 2>&1 || true
        echo_warn "Trying fallback to manifests..."
        # Fallback to manifests with OTel env vars
        if [ -f "manifests/base/deployment.yaml" ]; then
            echo "Deploying using Kubernetes manifests..."
            cat manifests/base/deployment.yaml | \
                sed "s|image:.*|image: ${IMAGE_NAME}|" | \
                sed 's|imagePullPolicy:.*|imagePullPolicy: Never|' | \
                kubectl apply -f - || true
            
            # Add OTel environment variables
            echo "Adding OpenTelemetry environment variables..."
            kubectl set env deployment/$APP_NAME \
                OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:4317 \
                OTEL_SERVICE_NAME=$APP_NAME \
                OTEL_RESOURCE_ATTRIBUTES="service.name=$APP_NAME,service.version=0.1.0,environment=local" \
                OTEL_EXPORTER_OTLP_INSECURE=true \
                -n $APP_NAMESPACE || true
            
            kubectl apply -f manifests/base/service.yaml || true
            echo_info "Application deployed via manifests"
        else
            echo_error "Neither Helm chart nor manifests found. Cannot deploy application."
            exit 1
        fi
    fi
else
    echo_warn "values-local-testing.yaml not found, using manifests..."
    # Fallback to manifests with OTel env vars
    if [ -f "manifests/base/deployment.yaml" ]; then
        echo "Deploying using Kubernetes manifests..."
        echo "  Image: $IMAGE_NAME"
        echo "  Namespace: $APP_NAMESPACE"
        cat manifests/base/deployment.yaml | \
            sed "s|image:.*|image: ${IMAGE_NAME}|" | \
            sed 's|imagePullPolicy:.*|imagePullPolicy: Never|' | \
            kubectl apply -f - || true
        
        # Add OTel environment variables
        echo "Adding OpenTelemetry environment variables..."
        kubectl set env deployment/$APP_NAME \
            OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:4317 \
            OTEL_SERVICE_NAME=$APP_NAME \
            OTEL_RESOURCE_ATTRIBUTES="service.name=$APP_NAME,service.version=0.1.0,environment=local" \
            OTEL_EXPORTER_OTLP_INSECURE=true \
            -n $APP_NAMESPACE || true
        
        kubectl apply -f manifests/base/service.yaml || true
        echo_info "Application deployed via manifests"
    else
        echo_error "Neither Helm chart values nor manifests found. Cannot deploy application."
        exit 1
    fi
fi

echo "Waiting for application deployment to be ready..."
# Try multiple label selectors (Helm chart uses app.kubernetes.io/name, manifests might use app)
APP_READY=false
if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=$APP_NAME -n $APP_NAMESPACE --timeout=2m >/dev/null 2>&1; then
    echo_info "Application pods are ready (app.kubernetes.io/name=$APP_NAME)"
    APP_READY=true
elif kubectl wait --for=condition=ready pod -l app=$APP_NAME -n $APP_NAMESPACE --timeout=2m >/dev/null 2>&1; then
    echo_info "Application pods are ready (app=$APP_NAME)"
    APP_READY=true
elif kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=$APP_NAME -n $APP_NAMESPACE --timeout=2m >/dev/null 2>&1; then
    echo_info "Application pods are ready (app.kubernetes.io/instance=$APP_NAME)"
    APP_READY=true
fi

if [ "$APP_READY" = "false" ]; then
    echo_warn "Application pods may not be ready yet. Checking status..."
    echo "Pods with Helm labels:"
    kubectl get pods -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME || true
    echo "Pods with app label:"
    kubectl get pods -n $APP_NAMESPACE -l app=$APP_NAME || true
    echo "All pods in namespace:"
    kubectl get pods -n $APP_NAMESPACE || true
    echo "Deployment status:"
    kubectl describe deployment $APP_NAME -n $APP_NAMESPACE | tail -30 || true
fi

# Verify deployment exists
DEPLOYMENT_NAME=$(kubectl get deployment -n $APP_NAMESPACE -o jsonpath='{.items[?(@.metadata.name=="'$APP_NAME'")].metadata.name}' 2>/dev/null || echo "")
if [ -n "$DEPLOYMENT_NAME" ]; then
    echo_info "Application deployment exists: $DEPLOYMENT_NAME"
    kubectl get deployment $DEPLOYMENT_NAME -n $APP_NAMESPACE
else
    echo_error "Application deployment not found: $APP_NAME"
    echo "Checking what's deployed in namespace $APP_NAMESPACE:"
    kubectl get all -n $APP_NAMESPACE || true
    echo "Checking Helm releases:"
    helm list -n $APP_NAMESPACE || true
    exit 1
fi

echo_info "Application deployed with OpenTelemetry"

# Step 9b: Verify HTTPRoute deployment (if Gateway API is available)
echo ""
echo_step "Step 9b: Verifying HTTPRoute deployment..."

# Note: HTTPRoute is deployed automatically by Helm chart if gateway.enabled=true
# In production, this is enabled by default (assuming Traefik + Gateway API is pre-deployed)
# Check if Gateway API CRDs exist
if kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1; then
    echo "Gateway API detected - Checking HTTPRoute status..."
    # Check if HTTPRoute was deployed by Helm (check by labels first, then by name pattern)
    # Helm creates HTTPRoute with name matching the chart's fullname template
    HTTPROUTE_NAME=$(kubectl get httproute -n $APP_NAMESPACE -o jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io/name=="dm-nkp-gitops-custom-app")].metadata.name}' 2>/dev/null | cut -d' ' -f1)
    if [ -z "$HTTPROUTE_NAME" ]; then
        # Try by release name pattern (Helm fullname might be release-name or release-name-chart-name)
        HTTPROUTE_NAME=$(kubectl get httproute -n $APP_NAMESPACE -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -i "$APP_NAME" | head -1)
    fi
    if [ -z "$HTTPROUTE_NAME" ]; then
        # Try any HTTPRoute in namespace (should only be one for this app)
        HTTPROUTE_NAME=$(kubectl get httproute -n $APP_NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    fi
    
    if [ -n "$HTTPROUTE_NAME" ]; then
        echo_info "HTTPRoute deployed via Helm chart: $HTTPROUTE_NAME"
        kubectl get httproute -n $APP_NAMESPACE $HTTPROUTE_NAME
        echo ""
        echo "  HTTPRoute status (checking parent Gateway acceptance):"
        kubectl get httproute -n $APP_NAMESPACE $HTTPROUTE_NAME -o jsonpath='{.status.parents[*].conditions[*].message}' 2>/dev/null && echo "" || \
        kubectl get httproute -n $APP_NAMESPACE $HTTPROUTE_NAME -o jsonpath='{.status.parents[*].conditions[*].status}' 2>/dev/null || \
        echo "  (HTTPRoute created - check acceptance with: kubectl describe httproute -n $APP_NAMESPACE $HTTPROUTE_NAME)"
    else
        echo_warn "HTTPRoute not found. Checking Helm values..."
        if helm get values $APP_NAME --namespace $APP_NAMESPACE 2>/dev/null | grep -q "gateway:" || \
           helm get values $APP_NAME --namespace $APP_NAMESPACE 2>/dev/null | grep -q "enabled: true"; then
            echo_warn "Gateway may be enabled in Helm values but HTTPRoute not found. Checking all HTTPRoutes:"
            kubectl get httproute -n $APP_NAMESPACE || echo "  No HTTPRoutes found in namespace"
        else
            echo_info "HTTPRoute is disabled in Helm values (this is normal if Gateway API is not installed)"
            echo "  To enable: helm upgrade $APP_NAME chart/dm-nkp-gitops-custom-app --set gateway.enabled=true -n $APP_NAMESPACE"
        fi
    fi
elif kubectl get crd ingressroutes.traefik.containo.us >/dev/null 2>&1; then
    # Traefik Classic mode - Note: IngressRoute is not in Helm chart (only HTTPRoute for Gateway API)
    echo "Traefik Classic mode detected (no Gateway API)"
    echo "Note: This chart deploys HTTPRoute for Gateway API only. IngressRoute would need manual deployment."
    echo "  For production, use Traefik + Gateway API (recommended standard approach)"
else
    echo "Neither Gateway API nor Traefik Classic detected"
    echo "  - Install Traefik with Gateway API: ./scripts/setup-gateway-api-helm.sh $CLUSTER_NAME"
    echo "  - Install Traefik Classic: ./scripts/setup-traefik-helm.sh $CLUSTER_NAME"
    echo "  Note: Gateway API is the standard approach (recommended for production)"
fi

# Step 10: Generate traffic to create metrics, logs, and traces
echo ""
echo_step "Step 10: Generating traffic to create telemetry data..."

# Port forward in background
kubectl port-forward -n $APP_NAMESPACE svc/$APP_NAME 8080:8080 >/dev/null 2>&1 &
PF_PID=$!
sleep 3

# Generate traffic
echo "Generating requests..."
for _ in {1..100}; do
    curl -s http://localhost:8080/ >/dev/null 2>&1 || true
    sleep 0.1
done

kill $PF_PID 2>/dev/null || true
echo_info "Generated 100 requests"

# Wait a bit for telemetry to be collected
sleep 5

# Step 11: Configure Grafana datasources (Loki and Tempo)
echo ""
echo_step "Step 11: Configuring Grafana datasources..."
echo "Configuring Loki and Tempo datasources in Grafana..."

# Get Grafana admin password
GRAFANA_PASSWORD=$(kubectl get secret -n $OBSERVABILITY_NAMESPACE prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")

# Wait for Grafana to be ready
echo "Waiting for Grafana to be ready..."
set +e  # Temporarily disable exit on error
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n $OBSERVABILITY_NAMESPACE --timeout=2m >/dev/null 2>&1 || echo_warn "Grafana may not be fully ready yet"
set -e  # Re-enable exit on error

# Port forward to Grafana in background
LOCAL_PORT=3000
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana $LOCAL_PORT:80 >/dev/null 2>&1 &
GRAFANA_PF_PID=$!
sleep 5

# Wait for Grafana API to be ready
echo "Waiting for Grafana API..."
API_READY=false
for i in {1..30}; do
    if curl -s -u "admin:${GRAFANA_PASSWORD}" "http://localhost:${LOCAL_PORT}/api/health" >/dev/null 2>&1; then
        API_READY=true
        break
    fi
    sleep 1
done

if [ "$API_READY" = "true" ]; then
    echo_info "Grafana API is ready"
    
    # Verify Loki service exists
    set +e  # Temporarily disable exit on error
    if kubectl get svc loki -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
        LOKI_SVC="loki"
        LOKI_PORT="3100"
    elif kubectl get svc loki-gateway -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
        LOKI_SVC="loki-gateway"
        LOKI_PORT="80"
    else
        LOKI_SVC=""
        echo_warn "Loki service not found, skipping Loki datasource configuration"
    fi
    set -e  # Re-enable exit on error
    
    # Verify Tempo service exists
    set +e  # Temporarily disable exit on error
    if kubectl get svc tempo -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
        TEMPO_SVC="tempo"
        TEMPO_PORT="3200"
    elif kubectl get svc tempo-gateway -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
        TEMPO_SVC="tempo-gateway"
        TEMPO_PORT="80"
    else
        TEMPO_SVC=""
        echo_warn "Tempo service not found, skipping Tempo datasource configuration"
    fi
    set -e  # Re-enable exit on error
    
    # Configure Loki datasource
    if [ -n "$LOKI_SVC" ]; then
        echo "Configuring Loki datasource..."
        LOKI_URL="http://${LOKI_SVC}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:${LOKI_PORT}"
        LOKI_JSON=$(cat <<EOF
{
  "name": "Loki",
  "type": "loki",
  "url": "${LOKI_URL}",
  "access": "proxy",
  "uid": "loki",
  "editable": true,
  "jsonData": {
    "maxLines": 1000
  }
}
EOF
)
        
        # Check if Loki datasource already exists
        EXISTING_LOKI=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
            "http://localhost:${LOCAL_PORT}/api/datasources/name/Loki" 2>/dev/null)
        
        if echo "$EXISTING_LOKI" | grep -q '"id"'; then
            # Update existing datasource
            LOKI_ID=$(echo "$EXISTING_LOKI" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
            LOKI_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
                -u "admin:${GRAFANA_PASSWORD}" \
                -H "Content-Type: application/json" \
                -d "${LOKI_JSON}" \
                "http://localhost:${LOCAL_PORT}/api/datasources/${LOKI_ID}" 2>/dev/null)
            LOKI_HTTP_CODE=$(echo "$LOKI_RESPONSE" | tail -n1)
            if [ "$LOKI_HTTP_CODE" = "200" ]; then
                echo_info "Loki datasource updated"
            else
                echo_warn "Failed to update Loki datasource (HTTP $LOKI_HTTP_CODE)"
            fi
        else
            # Create new datasource
            LOKI_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
                -u "admin:${GRAFANA_PASSWORD}" \
                -H "Content-Type: application/json" \
                -d "${LOKI_JSON}" \
                "http://localhost:${LOCAL_PORT}/api/datasources" 2>/dev/null)
            LOKI_HTTP_CODE=$(echo "$LOKI_RESPONSE" | tail -n1)
            if [ "$LOKI_HTTP_CODE" = "200" ] || [ "$LOKI_HTTP_CODE" = "201" ]; then
                echo_info "Loki datasource created"
            else
                echo_warn "Failed to create Loki datasource (HTTP $LOKI_HTTP_CODE)"
                echo "Response: $(echo "$LOKI_RESPONSE" | head -n-1)"
            fi
        fi
    else
        echo_warn "Skipping Loki datasource configuration (service not found)"
    fi
    
    # Configure Tempo datasource
    if [ -n "$TEMPO_SVC" ]; then
        echo "Configuring Tempo datasource..."
        TEMPO_URL="http://${TEMPO_SVC}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:${TEMPO_PORT}"
        TEMPO_JSON=$(cat <<EOF
{
  "name": "Tempo",
  "type": "tempo",
  "url": "${TEMPO_URL}",
  "access": "proxy",
  "uid": "tempo",
  "editable": true,
  "jsonData": {
    "httpMethod": "GET",
    "serviceMap": {
      "datasourceUid": "prometheus"
    },
    "nodeGraph": {
      "enabled": true
    },
    "search": {
      "hide": false
    },
    "tracesToLogs": {
      "datasourceUid": "loki",
      "tags": ["job", "instance", "pod", "namespace", "service.name"],
      "mappedTags": [
        {
          "key": "service.name",
          "value": "service"
        }
      ],
      "mapTagNamesEnabled": false,
      "spanStartTimeShift": "1h",
      "spanEndTimeShift": "1h",
      "filterByTraceID": false,
      "filterBySpanID": false
    },
    "tracesToMetrics": {
      "datasourceUid": "prometheus",
      "tags": [
        {
          "key": "service.name",
          "value": "service"
        },
        {
          "key": "job"
        }
      ],
      "queries": [
        {
          "name": "Sample query",
          "query": "sum(rate(tempo_spanmetrics_latency_bucket{\${__tags}}[5m]))"
        }
      ]
    }
  }
}
EOF
)
    
    # Check if Tempo datasource already exists
    EXISTING_TEMPO=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
        "http://localhost:${LOCAL_PORT}/api/datasources/name/Tempo" 2>/dev/null)
    
    if echo "$EXISTING_TEMPO" | grep -q '"id"'; then
        # Update existing datasource
        TEMPO_ID=$(echo "$EXISTING_TEMPO" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
        TEMPO_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
            -u "admin:${GRAFANA_PASSWORD}" \
            -H "Content-Type: application/json" \
            -d "${TEMPO_JSON}" \
            "http://localhost:${LOCAL_PORT}/api/datasources/${TEMPO_ID}" 2>/dev/null)
        TEMPO_HTTP_CODE=$(echo "$TEMPO_RESPONSE" | tail -n1)
        if [ "$TEMPO_HTTP_CODE" = "200" ]; then
            echo_info "Tempo datasource updated"
        else
            echo_warn "Failed to update Tempo datasource (HTTP $TEMPO_HTTP_CODE)"
        fi
    else
        # Create new datasource
        TEMPO_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
            -u "admin:${GRAFANA_PASSWORD}" \
            -H "Content-Type: application/json" \
            -d "${TEMPO_JSON}" \
            "http://localhost:${LOCAL_PORT}/api/datasources" 2>/dev/null)
        TEMPO_HTTP_CODE=$(echo "$TEMPO_RESPONSE" | tail -n1)
        if [ "$TEMPO_HTTP_CODE" = "200" ] || [ "$TEMPO_HTTP_CODE" = "201" ]; then
            echo_info "Tempo datasource created"
        else
            echo_warn "Failed to create Tempo datasource (HTTP $TEMPO_HTTP_CODE)"
            echo "Response: $(echo "$TEMPO_RESPONSE" | head -n-1)"
        fi
    fi
    else
        echo_warn "Skipping Tempo datasource configuration (service not found)"
    fi
    
    # Kill port-forward
    kill $GRAFANA_PF_PID 2>/dev/null || true
    wait $GRAFANA_PF_PID 2>/dev/null || true
    
    if [ -n "$LOKI_SVC" ] || [ -n "$TEMPO_SVC" ]; then
        echo_info "Grafana datasources configured"
    else
        echo_warn "No datasources were configured (services not found)"
    fi
else
    echo_warn "Grafana API not ready, skipping datasource configuration"
    kill $GRAFANA_PF_PID 2>/dev/null || true
    echo "You can configure datasources manually later:"
    echo "  - Loki: http://loki.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:3100"
    echo "  - Tempo: http://tempo.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:3200"
fi

# Step 12: Display access information
echo ""
echo "=========================================="
echo "  ✅ Setup Complete!"
echo "=========================================="
echo ""
echo_info "Application is running in kind cluster: $CLUSTER_NAME"
echo ""
echo "📊 OpenTelemetry Observability Stack:"
echo ""
echo "🌐 Grafana Dashboard (Metrics, Logs, Traces):"
echo "  1. Port forward to Grafana:"
echo "     kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana 3000:80"
echo ""
echo "  2. Open browser:"
echo "     http://localhost:3000"
echo ""
echo "  3. Login credentials:"
echo "     Username: admin"
GRAFANA_PASSWORD=$(kubectl get secret -n $OBSERVABILITY_NAMESPACE prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")
echo "     Password: $GRAFANA_PASSWORD"
echo "     (Or run: kubectl get secret -n $OBSERVABILITY_NAMESPACE prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
echo ""
echo "  4. Data sources configured automatically:"
echo "     ✅ Prometheus: http://prometheus-kube-prometheus-prometheus.$OBSERVABILITY_NAMESPACE.svc.cluster.local:9090"
echo "     ✅ Loki: http://loki.$OBSERVABILITY_NAMESPACE.svc.cluster.local:3100"
echo "     ✅ Tempo: http://tempo.$OBSERVABILITY_NAMESPACE.svc.cluster.local:3200"
echo "     (If datasources are missing, check Step 11 output above)"
echo ""
echo "  5. View dashboards:"
echo "     - Application dashboards should auto-discover from ConfigMaps with label grafana_dashboard=1"
echo ""
echo "📈 Prometheus (Metrics Query):"
echo "  1. Port forward:"
echo "     kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo ""
echo "  2. Open browser:"
echo "     http://localhost:9090"
echo ""
echo "  3. Try queries:"
echo "     otelcol_receiver_accepted_metrics"
echo "     otelcol_processor_batch_send_size"
echo ""
echo "🔍 OTel Collector:"
echo "  kubectl logs -n $OBSERVABILITY_NAMESPACE -l component=otel-collector --tail=50"
echo ""
echo "📝 Application Logs (via OTel Collector → Loki):"
echo "  kubectl logs -n $APP_NAMESPACE -l app=$APP_NAME --tail=50"
echo ""
echo "🔗 Application Access:"
echo ""
echo "  Option 1: Port Forward (Direct Service Access)"
echo "    1. Port forward to application service:"
echo "       kubectl port-forward -n $APP_NAMESPACE svc/$APP_NAME 8080:8080"
echo ""
echo "    2. Access application:"
echo "       curl http://localhost:8080/"
echo "       curl http://localhost:8080/health"
echo "       curl http://localhost:8080/ready"
echo ""
echo "  Option 2: Via Traefik + Gateway API (if Traefik with Gateway API support is installed)"
if kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1 && kubectl get deployment -n traefik-system traefik >/dev/null 2>&1; then
    echo "    ✅ Traefik with Gateway API detected - HTTPRoute deployed automatically via Helm chart"
    echo ""
    echo "    1. Port forward to Traefik Gateway:"
    echo "       kubectl port-forward -n traefik-system svc/traefik 8080:80"
    echo ""
    echo "    2. Add hostname to /etc/hosts (one-time setup):"
    echo "       echo \"127.0.0.1 dm-nkp-gitops-custom-app.local\" | sudo tee -a /etc/hosts"
    echo ""
    echo "    3. Access application via hostname:"
    echo "       curl http://dm-nkp-gitops-custom-app.local/"
    echo "       curl http://dm-nkp-gitops-custom-app.local/health"
    echo "       curl http://dm-nkp-gitops-custom-app.local/ready"
    echo ""
    echo "    Note: If using NodePort in kind, you can also access directly via node IP:"
    echo "      NODE_IP=\$(docker inspect ${CLUSTER_NAME}-control-plane --format='{{.NetworkSettings.Networks.kind.IPAddress}}' 2>/dev/null || echo \"localhost\")"
    echo "      curl -H \"Host: dm-nkp-gitops-custom-app.local\" http://\${NODE_IP}:30080/"
    echo ""
    echo "    Verify HTTPRoute status:"
    echo "      kubectl get httproute -n $APP_NAMESPACE"
else
    echo "    ⚠️  Traefik with Gateway API not installed."
    echo "    Install with: ./scripts/setup-gateway-api-helm.sh $CLUSTER_NAME"
fi
echo ""
echo "  Option 3: Via Traefik IngressRoute (if Traefik in classic mode is installed - not recommended)"
if kubectl get crd ingressroutes.traefik.containo.us >/dev/null 2>&1 && \
   ! kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1; then
    echo "    ⚠️  Traefik Classic mode detected - uses IngressRoute (Traefik proprietary CRD)"
    echo "    Note: For production, use Traefik + Gateway API (recommended standard approach)"
    echo ""
    echo "    1. Port forward to Traefik:"
    echo "       kubectl port-forward -n traefik-system svc/traefik 8080:80"
    echo ""
    echo "    2. Add hostname to /etc/hosts:"
    echo "       echo \"127.0.0.1 dm-nkp-gitops-custom-app.local\" | sudo tee -a /etc/hosts"
    echo ""
    echo "    3. Access application via hostname:"
    echo "       curl http://dm-nkp-gitops-custom-app.local/"
    echo "       curl http://dm-nkp-gitops-custom-app.local/health"
else
    echo "    Traefik Classic mode not detected (Gateway API is preferred)"
fi
echo ""
echo "  📝 Important Notes:"
echo "     - Traefik + Gateway API and Traefik Classic are mutually exclusive"
echo "     - Production: Traefik + Gateway API is pre-deployed by platform team"
echo "     - HTTPRoute is automatically deployed when app is deployed (if gateway.enabled=true)"
echo "     - In production, gateway.enabled=true by default (assumes platform dependency is installed)"
echo ""
echo "🧹 Cleanup (when done):"
echo "  kind delete cluster --name $CLUSTER_NAME"
echo ""
echo "📚 For more information:"
echo "  - See docs/OPENTELEMETRY_QUICK_START.md for quick start guide"
echo "  - See docs/RUNNING_E2E_TESTS.md for e2e testing guide"
echo "  - See docs/opentelemetry-workflow.md for complete workflow"
echo ""
echo "Press Ctrl+C to exit (cluster will remain for inspection)"
echo ""

# Keep script running and show status
while true; do
    sleep 30
    echo ""
    echo_step "Status check:"
    echo "Application pods:"
    # Try multiple label selectors
    kubectl get pods -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME 2>/dev/null | grep -v NAME || \
    kubectl get pods -n $APP_NAMESPACE -l app=$APP_NAME 2>/dev/null | grep -v NAME || \
    kubectl get pods -n $APP_NAMESPACE 2>/dev/null | grep -i "$APP_NAME" | grep -v NAME || \
    echo_warn "App pods not found"
    echo ""
    echo "Observability pods:"
    kubectl get pods -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -iE "(otel.*collector|prometheus|grafana|loki|tempo)" | grep -v NAME || echo_warn "Observability pods not found"
done
