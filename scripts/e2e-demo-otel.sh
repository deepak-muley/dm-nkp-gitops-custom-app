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

# Cross-platform timeout wrapper
# Uses system timeout if available, otherwise relies on kubectl's own timeout parameter
run_with_timeout() {
    local timeout_sec=$1
    shift

    # Check if timeout command exists (Linux) or gtimeout (macOS with coreutils)
    if command -v timeout >/dev/null 2>&1; then
        timeout $timeout_sec "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout $timeout_sec "$@"
    else
        # On macOS without timeout: kubectl wait already has --timeout parameter
        # Just run the command directly - kubectl will handle its own timeout
        "$@"
    fi
}

cleanup() {
    echo ""
    echo_warn "Cleaning up..."
    # Kill any background port forwards
    pkill -f "kubectl port-forward" 2>/dev/null || true
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
set +e  # Temporarily disable exit on error for cluster check
CLUSTER_EXISTS=false
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    CLUSTER_EXISTS=true
fi
set -e  # Re-enable exit on error

if [ "$CLUSTER_EXISTS" = "true" ]; then
    echo_info "Cluster '$CLUSTER_NAME' already exists"
else
    echo "Creating kind cluster..."
    if kind create cluster --name $CLUSTER_NAME >/dev/null 2>&1; then
        echo_info "Kind cluster created"
    else
        echo_error "Failed to create cluster"
        echo_warn "This may be due to Docker permissions. Please ensure Docker is running and accessible."
        echo_warn "You can check with: docker ps"
        exit 1
    fi
fi

# Set kubectl context
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true

# Step 6: Load image into kind
echo ""
echo_step "Step 6: Loading image into kind cluster..."
set +e  # Temporarily disable exit on error
if kind load docker-image $IMAGE_NAME --name $CLUSTER_NAME >/dev/null 2>&1; then
    echo_info "Image loaded into kind"
else
    echo_warn "Failed to load image (may already be loaded or image doesn't exist)"
    echo_warn "Checking if image exists locally..."
    if docker images | grep -q "${IMAGE_NAME%:*}"; then
        echo_info "Image exists locally, attempting to load again..."
        kind load docker-image $IMAGE_NAME --name $CLUSTER_NAME 2>&1 || echo_warn "Image load failed, but continuing (may already be in cluster)"
    else
        echo_warn "Image not found locally. If build was skipped, this is expected."
        echo_warn "Continuing - existing image in cluster will be used if available"
    fi
fi
set -e  # Re-enable exit on error

# Step 7: Deploy observability stack (OTel Collector, Prometheus, Loki, Tempo, Grafana)
echo ""
echo_step "Step 7: Deploying OpenTelemetry observability stack..."

# Check if observability stack is already installed
OBSERVABILITY_INSTALLED=false
if helm list -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -qE "prometheus|loki|tempo"; then
    echo_info "Observability stack charts already installed, checking status..."
    OBSERVABILITY_INSTALLED=true
fi

OTEL_DEPLOYED=false
if [ "$OBSERVABILITY_INSTALLED" = "false" ] && [ -f "scripts/setup-observability-stack.sh" ]; then
    echo "Using scripts/setup-observability-stack.sh..."
    if bash scripts/setup-observability-stack.sh; then
        echo_info "Observability stack deployed"
        OTEL_DEPLOYED=true
    else
        echo_warn "setup-observability-stack.sh failed, checking what was installed..."
        # Check what got installed before the failure
        if helm list -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -qE "prometheus|loki|tempo"; then
            echo_info "Some observability charts were installed, will skip manual installation to avoid duplicates"
            OTEL_DEPLOYED=true
        else
            echo_warn "No observability charts found, will try manual deployment..."
            OTEL_DEPLOYED=false
        fi
    fi
elif [ "$OBSERVABILITY_INSTALLED" = "true" ]; then
    echo_info "Observability stack already installed, skipping setup script"
    OTEL_DEPLOYED=true
    # Still need to ensure OTel Operator and Collector CR exist
    echo "Checking OTel Operator status..."
    if kubectl get crd opentelemetrycollectors.opentelemetry.io >/dev/null 2>&1; then
        echo_info "OTel Operator CRD exists"
    else
        echo_warn "OTel Operator CRD not found, OTel Operator may not be installed"
    fi
fi

# If setup script failed or doesn't exist, deploy manually (only if charts are not already installed)
if [ "$OTEL_DEPLOYED" = "false" ]; then
    echo_warn "Deploying observability stack manually..."

    # Create namespace
    kubectl create namespace $OBSERVABILITY_NAMESPACE --dry-run=client -o yaml | kubectl apply -f - || true

    # Add Helm repos
    echo "Adding Helm repositories..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
    helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
    helm repo update || echo_warn "Helm repo update had issues, continuing..."

    # Install Prometheus + Grafana
    # Check if Prometheus is already installed
    if helm list -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -q "^prometheus[[:space:]]"; then
        echo_info "Prometheus already installed, skipping installation"
    else
        echo "Installing Prometheus and Grafana..."
        # Handle CRD version mismatch by automatically uninstalling and reinstalling if needed
        INSTALL_ERROR_FILE="/tmp/prometheus-install-$$.log"
        if helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
      --namespace $OBSERVABILITY_NAMESPACE \
      --create-namespace \
      --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
      --set prometheus.prometheusSpec.retention=1h \
      --set grafana.adminPassword=admin \
      --set grafana.sidecar.datasources.enabled=true \
      --set grafana.sidecar.datasources.searchNamespace=ALL \
      --set grafana.sidecar.dashboards.enabled=true \
      --set grafana.sidecar.dashboards.searchNamespace=ALL \
      --wait --timeout=2m 2>&1 | tee "$INSTALL_ERROR_FILE"; then
        echo_info "Prometheus and Grafana installed successfully"
        rm -f "$INSTALL_ERROR_FILE"
    else
        INSTALL_ERROR=$(cat "$INSTALL_ERROR_FILE" 2>/dev/null || echo "")
        if echo "$INSTALL_ERROR" | grep -q "field not declared in schema"; then
            echo_warn "Upgrade failed due to CRD schema mismatch (ServiceMonitor CRD version incompatibility)"
            echo_warn "Automatically uninstalling and cleaning up CRDs to fix version mismatch..."
            helm uninstall prometheus -n $OBSERVABILITY_NAMESPACE 2>/dev/null || true
            sleep 3
            # Delete problematic ServiceMonitor resources that might have incompatible fields
            echo_warn "Cleaning up ServiceMonitor resources with incompatible schema..."
            kubectl delete servicemonitor -n $OBSERVABILITY_NAMESPACE --all --ignore-not-found=true 2>/dev/null || true
            kubectl delete prometheusrule -n $OBSERVABILITY_NAMESPACE --all --ignore-not-found=true 2>/dev/null || true
            # Wait for resources to be fully deleted
            sleep 5
            # Reinstall with fresh CRDs (Helm will install updated CRDs)
            echo_warn "Reinstalling Prometheus with fresh CRDs..."
            if helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
              --namespace $OBSERVABILITY_NAMESPACE \
              --create-namespace \
              --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
              --set prometheus.prometheusSpec.retention=1h \
              --set grafana.adminPassword=admin \
              --set grafana.sidecar.datasources.enabled=true \
              --set grafana.sidecar.datasources.searchNamespace=ALL \
              --set grafana.sidecar.dashboards.enabled=true \
              --set grafana.sidecar.dashboards.searchNamespace=ALL \
              --wait --timeout=2m 2>&1 | tee "$INSTALL_ERROR_FILE"; then
                echo_info "Prometheus reinstalled successfully after CRD fix"
                rm -f "$INSTALL_ERROR_FILE"
            else
                REINSTALL_ERROR=$(cat "$INSTALL_ERROR_FILE" 2>/dev/null || echo "")
                if echo "$REINSTALL_ERROR" | grep -q "field not declared in schema"; then
                    echo_warn "Still seeing CRD schema issues. Deleting CRDs and retrying..."
                    # Delete the CRDs themselves if they're still causing issues
                    kubectl delete crd servicemonitors.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || true
                    kubectl delete crd prometheusrules.monitoring.coreos.com --ignore-not-found=true 2>/dev/null || true
                    sleep 5
                    # Final reinstall - Helm will install fresh CRDs
                    if helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
                      --namespace $OBSERVABILITY_NAMESPACE \
                      --create-namespace \
                      --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
                      --set prometheus.prometheusSpec.retention=1h \
                      --set grafana.adminPassword=admin \
                      --set grafana.sidecar.datasources.enabled=true \
                      --set grafana.sidecar.datasources.searchNamespace=ALL \
                      --set grafana.sidecar.dashboards.enabled=true \
                      --set grafana.sidecar.dashboards.searchNamespace=ALL \
                      --wait --timeout=5m; then
                        echo_info "Prometheus reinstalled successfully after CRD deletion"
                    else
                        echo_warn "Prometheus reinstallation still had issues, continuing..."
                    fi
                else
                    echo_warn "Prometheus reinstallation had issues: $(echo "$REINSTALL_ERROR" | head -3)"
                fi
                rm -f "$INSTALL_ERROR_FILE"
            fi
        else
            echo_warn "Prometheus installation had issues: $(echo "$INSTALL_ERROR" | head -3)"
        fi
        rm -f "$INSTALL_ERROR_FILE"
        fi
    fi

    # Install Loki 3.0+ (using grafana/loki chart with monolithic mode for single-node kind clusters)
    # Loki 3.0+ supports native OTLP ingestion which is required for OTel Collector logs
    # Check if Loki is already installed
    if helm list -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -q "^loki[[:space:]]"; then
        echo_info "Loki already installed, checking version..."
        LOKI_VERSION=$(helm list -n $OBSERVABILITY_NAMESPACE -o json 2>/dev/null | jq -r '.[] | select(.name=="loki") | .app_version' || echo "unknown")
        echo_info "Current Loki version: $LOKI_VERSION"
        # Check if it's Loki 3.0+ (needed for OTLP support)
        if [[ "$LOKI_VERSION" =~ ^[0-2]\. ]] && [[ ! "$LOKI_VERSION" =~ ^3\. ]]; then
            echo_warn "Loki version is older than 3.0, upgrading for OTLP support..."
            helm uninstall loki -n $OBSERVABILITY_NAMESPACE --wait 2>/dev/null || true
            sleep 5
        else
            echo_info "Loki 3.0+ already installed, skipping upgrade"
        fi
    fi

    # Install/upgrade Loki 3.0+ with OTLP support
    if ! helm list -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -q "^loki[[:space:]]"; then
        echo "Installing Loki 3.0+ with OTLP support (monolithic mode for local testing)..."
        # Using grafana/loki chart with:
        # - deploymentMode: SingleBinary (monolithic mode for simplicity)
        # - OTLP receiver enabled on port 4318 (HTTP) for OTel Collector logs
        # - Filesystem storage (suitable for local testing)
        if helm upgrade --install loki grafana/loki \
          --namespace $OBSERVABILITY_NAMESPACE \
          --set deploymentMode=SingleBinary \
          --set loki.auth_enabled=false \
          --set loki.commonConfig.replication_factor=1 \
          --set loki.storage.type=filesystem \
          --set loki.schemaConfig.configs[0].from="2024-01-01" \
          --set loki.schemaConfig.configs[0].store=tsdb \
          --set loki.schemaConfig.configs[0].object_store=filesystem \
          --set loki.schemaConfig.configs[0].schema=v13 \
          --set loki.schemaConfig.configs[0].index.prefix=loki_index_ \
          --set loki.schemaConfig.configs[0].index.period=24h \
          --set loki.limits_config.allow_structured_metadata=true \
          --set loki.limits_config.volume_enabled=true \
          --set loki.limits_config.retention_period=168h \
          --set singleBinary.replicas=1 \
          --set singleBinary.persistence.enabled=true \
          --set singleBinary.persistence.size=10Gi \
          --set read.replicas=0 \
          --set write.replicas=0 \
          --set backend.replicas=0 \
          --set gateway.enabled=true \
          --set gateway.replicas=1 \
          --set test.enabled=false \
          --set lokiCanary.enabled=false \
          --wait --timeout=5m; then
            echo_info "Loki 3.0+ installed successfully with OTLP support (monolithic mode)"
            echo_info "Loki OTLP endpoint: http://loki-gateway.$OBSERVABILITY_NAMESPACE.svc.cluster.local/otlp/v1/logs"
        else
            echo_warn "Loki 3.0+ installation had issues, continuing..."
        fi
    fi

    # Install Tempo with OTLP receiver enabled
    # Check if Tempo is already installed
    if helm list -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -q "^tempo[[:space:]]"; then
        echo_info "Tempo already installed, skipping installation"
    else
        echo "Installing Tempo with OTLP receiver enabled..."
        if helm upgrade --install tempo grafana/tempo \
          --namespace $OBSERVABILITY_NAMESPACE \
          --set serviceAccount.create=true \
          --set tempo.receivers.otlp.protocols.grpc.endpoint="0.0.0.0:4317" \
          --set tempo.receivers.otlp.protocols.http.endpoint="0.0.0.0:4318" \
          --set tempo.reportingEnabled=false \
          --wait --timeout=5m; then
            echo_info "Tempo installed successfully with OTLP receiver on ports 4317 (gRPC) and 4318 (HTTP)"
        else
            echo_warn "Tempo installation had issues, continuing..."
        fi
    fi

    # Install Logging Operator (for stdout/stderr log collection)
    # Note: NKP platform will have this pre-installed, but we install it for local testing
    LOGGING_OPERATOR_NAMESPACE="logging"
    echo ""
    echo "Installing Logging Operator (for stdout/stderr log collection)..."
    helm repo add kube-logging https://kube-logging.github.io/helm-charts 2>/dev/null || true
    helm repo update || true

    # Check if Logging Operator is already installed
    if helm list -n $LOGGING_OPERATOR_NAMESPACE 2>/dev/null | grep -qE "^logging-operator[[:space:]]"; then
        echo_info "Logging Operator already installed, skipping installation"
    else
        echo "Installing Logging Operator..."
        if helm upgrade --install logging-operator kube-logging/logging-operator \
          --namespace $LOGGING_OPERATOR_NAMESPACE \
          --create-namespace \
          --wait --timeout=5m; then
            echo_info "Logging Operator installed successfully"

            # Wait for Logging Operator to be ready
            echo "Waiting for Logging Operator to be ready..."
            set +e
            for i in {1..30}; do
                if kubectl get pods -n $LOGGING_OPERATOR_NAMESPACE -l app.kubernetes.io/name=logging-operator 2>/dev/null | grep -q Running; then
                    echo_info "Logging Operator is running"
                    break
                fi
                if [ $i -eq 30 ]; then
                    echo_warn "Logging Operator pods not ready after 2 minutes"
                fi
                sleep 2
            done
            set -e
        else
            echo_warn "Logging Operator installation had issues, continuing..."
        fi
    fi

    # Configure Logging Operator to send logs to Loki
    # Wait for Logging Operator CRDs to be available
    echo ""
    echo "Configuring Logging Operator to send logs to Loki..."
    set +e
    for i in {1..30}; do
        if kubectl get crd loggings.logging.banzaicloud.io >/dev/null 2>&1; then
            echo_info "Logging Operator CRDs are available"
            break
        fi
        if [ $i -eq 30 ]; then
            echo_warn "Logging Operator CRDs not found after 30 attempts"
            echo_warn "Logging Operator may not be fully installed"
        fi
        sleep 2
    done
    set -e

    # Get Loki gateway service for Logging Operator output
    # Loki 3.0+ uses loki-gateway service, older versions use loki-loki-distributed-gateway
    LOKI_GATEWAY_SVC=""
    LOKI_GATEWAY_PORT="80"

    # Try to find Loki gateway service (Loki 3.0+ naming)
    if kubectl get svc loki-gateway -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
        LOKI_GATEWAY_SVC="loki-gateway"
        LOKI_GATEWAY_PORT=$(kubectl get svc "$LOKI_GATEWAY_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http-metrics")].port}' 2>/dev/null || echo "80")
    elif kubectl get svc loki-loki-distributed-gateway -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
        LOKI_GATEWAY_SVC="loki-loki-distributed-gateway"
        LOKI_GATEWAY_PORT=$(kubectl get svc "$LOKI_GATEWAY_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null || echo "80")
    else
        # Fallback: search by labels
        LOKI_GATEWAY_SVC=$(kubectl get svc -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=loki,app.kubernetes.io/component=gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "loki-gateway")
        LOKI_GATEWAY_PORT=$(kubectl get svc "$LOKI_GATEWAY_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")
    fi

    echo_info "Found Loki gateway service: $LOKI_GATEWAY_SVC (port: $LOKI_GATEWAY_PORT)"
    LOKI_ENDPOINT="http://${LOKI_GATEWAY_SVC}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:${LOKI_GATEWAY_PORT}/loki/api/v1/push"

    # Create Logging resource (defines the logging system)
    if kubectl get crd loggings.logging.banzaicloud.io >/dev/null 2>&1; then
        if kubectl get logging default -n $LOGGING_OPERATOR_NAMESPACE >/dev/null 2>&1; then
            echo_info "Logging resource already exists, updating it..."
        else
            echo "Creating Logging resource..."
        fi

        LOGGING_YAML=$(cat <<EOF
apiVersion: logging.banzaicloud.io/v1beta1
kind: Logging
metadata:
  name: default
  namespace: ${LOGGING_OPERATOR_NAMESPACE}
spec:
  controlNamespace: ${LOGGING_OPERATOR_NAMESPACE}
EOF
)
        if echo "$LOGGING_YAML" | kubectl apply -f - 2>&1; then
            echo_info "Logging resource created/updated"
        else
            echo_warn "Failed to create/update Logging resource"
        fi

        # Create Output resource (defines where logs go - Loki)
        if kubectl get crd outputs.logging.banzaicloud.io >/dev/null 2>&1; then
            if kubectl get output loki -n $LOGGING_OPERATOR_NAMESPACE >/dev/null 2>&1; then
                echo_info "Loki Output resource already exists, updating it..."
            else
                echo "Creating Loki Output resource..."
            fi

            OUTPUT_YAML=$(cat <<EOF
apiVersion: logging.banzaicloud.io/v1beta1
kind: Output
metadata:
  name: loki
  namespace: ${LOGGING_OPERATOR_NAMESPACE}
spec:
  loki:
    url: ${LOKI_ENDPOINT}
    configure_kubernetes_labels: true
    buffer:
      type: file
      path: /buffers/loki
      flush_interval: 5s
      flush_mode: immediate
      retry_type: exponential_backoff
      retry_wait: 1s
      retry_max_interval: 60s
      retry_timeout: 60m
      chunk_limit_size: 1M
      total_limit_size: 500M
      overflow_action: block
EOF
)
            if echo "$OUTPUT_YAML" | kubectl apply -f - 2>&1; then
                echo_info "Loki Output resource created/updated"
            else
                echo_warn "Failed to create/update Loki Output resource"
            fi

            # Create Flow resource (defines what logs to collect and where to send them)
            if kubectl get crd flows.logging.banzaicloud.io >/dev/null 2>&1; then
                if kubectl get flow default -n $LOGGING_OPERATOR_NAMESPACE >/dev/null 2>&1; then
                    echo_info "Flow resource already exists, updating it..."
                else
                    echo "Creating Flow resource to collect all pod logs..."
                fi

                # Create Flow to collect logs from all pods (stdout/stderr)
                # Note: This collects logs from all pods by default
                # You can filter by namespace or labels if needed
                FLOW_YAML=$(cat <<EOF
apiVersion: logging.banzaicloud.io/v1beta1
kind: Flow
metadata:
  name: default
  namespace: ${LOGGING_OPERATOR_NAMESPACE}
spec:
  # Match all pods (stdout/stderr logs)
  # Logging Operator will automatically collect from all pods via Fluent Bit/D DaemonSet
  match:
    - select: {}  # Empty select matches all pods
  localOutputRefs:
    - loki
  filters:
    - parser:
        remove_key_name_field: true
        reserve_data: true
        parse:
          type: json
          time_key: time
          time_format: "%Y-%m-%dT%H:%M:%S.%NZ"
EOF
)
                if echo "$FLOW_YAML" | kubectl apply -f - 2>&1; then
                    echo_info "Flow resource created/updated (collecting stdout/stderr logs from all pods)"
                else
                    echo_warn "Failed to create/update Flow resource"
                fi
            else
                echo_warn "Flow CRD not found, skipping Flow creation"
            fi
        else
            echo_warn "Output CRD not found, skipping Output creation"
        fi
    else
        echo_warn "Logging CRD not found, skipping Logging Operator configuration"
        echo_warn "Logging Operator may not be fully installed yet"
    fi

    # Install cert-manager (required by OTel Operator for webhook certificates)
    echo "Installing cert-manager (required by OTel Operator)..."
    helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
    helm repo update || true

    if helm list -n cert-manager 2>/dev/null | grep -qE "^cert-manager[[:space:]]"; then
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
            run_with_timeout 15 kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=15s 2>/dev/null || echo_warn "cert-manager webhook may not be ready yet"
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
    if helm list -n opentelemetry-operator-system 2>/dev/null | grep -qE "^opentelemetry-operator[[:space:]]"; then
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

    # Wait for OTel Operator to be ready (check if it exists)
    OTel_OPERATOR_EXISTS=false
    if kubectl get pods -n opentelemetry-operator-system -l app.kubernetes.io/name=opentelemetry-operator 2>/dev/null | grep -q Running; then
        OTel_OPERATOR_EXISTS=true
        echo_info "OTel Operator is running"
    elif [ "$OTEL_DEPLOYED" = "true" ]; then
        echo "Waiting for OTel Operator to be ready..."
        set +e  # Temporarily disable exit on error
        if run_with_timeout 15 kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=opentelemetry-operator -n opentelemetry-operator-system --timeout=15s 2>/dev/null; then
            echo_info "OTel Operator is ready"
            OTel_OPERATOR_EXISTS=true
        else
            echo_warn "OTel Operator may not be fully ready yet, continuing..."
        fi
        set -e  # Re-enable exit on error
    fi

    # Create or update OpenTelemetryCollector instance (always check/update, regardless of installation method)
    if [ "$OTel_OPERATOR_EXISTS" = "true" ] || kubectl get crd opentelemetrycollectors.opentelemetry.io >/dev/null 2>&1; then
        echo "Checking for OpenTelemetryCollector instance..."
        if kubectl get opentelemetrycollector otel-collector -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
            echo_info "OpenTelemetryCollector instance already exists, will update it..."
            kubectl get opentelemetrycollector otel-collector -n $OBSERVABILITY_NAMESPACE 2>/dev/null
        else
            echo "Creating OpenTelemetryCollector instance..."
        fi

        # Wait for OTel Operator to be fully ready (CRD should be available)
        echo "Waiting for OpenTelemetryCollector CRD to be available..."
        set +e  # Temporarily disable exit on error
        for i in {1..30}; do
            if kubectl get crd opentelemetrycollectors.opentelemetry.io >/dev/null 2>&1; then
                echo_info "OpenTelemetryCollector CRD is available"
                break
            fi
            if [ $i -eq 30 ]; then
                echo_error "OpenTelemetryCollector CRD not found after 30 attempts"
                echo_warn "OTel Operator may not be fully installed. Please check:"
                echo_warn "  kubectl get pods -n opentelemetry-operator-system"
                echo_warn "  kubectl get crd | grep opentelemetry"
            fi
            sleep 2
        done
        set -e  # Re-enable exit on error

        # Get Tempo service name for exporter endpoint
        TEMPO_SVC_FOR_COLLECTOR="tempo"
        if ! kubectl get svc tempo -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
            TEMPO_SVC_FOR_COLLECTOR=$(kubectl get svc -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=tempo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "tempo")
        fi

        # Create OpenTelemetryCollector CR with config as object
        # In v1beta1, config field expects an object (not a YAML string)

        # Get Loki service URL for log export (Loki 3.0+ uses loki-gateway with OTLP support)
        LOKI_SVC_FOR_COLLECTOR=""
        LOKI_OTLP_PORT="80"
        if kubectl get svc loki-gateway -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
            LOKI_SVC_FOR_COLLECTOR="loki-gateway"
            LOKI_OTLP_PORT=$(kubectl get svc loki-gateway -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http-metrics")].port}' 2>/dev/null || echo "80")
        elif kubectl get svc -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=loki 2>/dev/null | grep -qi gateway; then
            LOKI_SVC_FOR_COLLECTOR=$(kubectl get svc -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=loki,app.kubernetes.io/component=gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        fi
        if [ -z "$LOKI_SVC_FOR_COLLECTOR" ]; then
            LOKI_SVC_FOR_COLLECTOR=$(kubectl get svc -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -iE "loki.*gateway|gateway.*loki" | head -1 | awk '{print $1}' || echo "")
        fi
        if [ -z "$LOKI_SVC_FOR_COLLECTOR" ] && kubectl get svc loki -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
            LOKI_SVC_FOR_COLLECTOR="loki"
        fi
        LOKI_SVC_FOR_COLLECTOR="${LOKI_SVC_FOR_COLLECTOR:-loki-gateway}"

        echo_info "Using Loki service for OTel Collector: $LOKI_SVC_FOR_COLLECTOR (OTLP port: $LOKI_OTLP_PORT)"

        # OTel Collector config for Loki 3.0+ with native OTLP support
        # Uses otlphttp exporter to send logs to Loki's /otlp endpoint
        COLLECTOR_CR_YAML=$(cat <<EOF
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: ${OBSERVABILITY_NAMESPACE}
spec:
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      batch: {}
      resource:
        attributes:
          - key: job
            value: otel-collector
            action: upsert
          - key: service.name
            value: dm-nkp-gitops-custom-app
            action: upsert
    exporters:
      prometheusremotewrite:
        endpoint: http://prometheus-kube-prometheus-prometheus.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:9090/api/v1/write
      prometheus:
        endpoint: 0.0.0.0:8889
        metric_expiration: 180m
        enable_open_metrics: true
      debug:
        verbosity: detailed
      otlp/tempo:
        endpoint: ${TEMPO_SVC_FOR_COLLECTOR}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:4317
        tls:
          insecure: true
      otlphttp/loki:
        endpoint: http://${LOKI_SVC_FOR_COLLECTOR}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:${LOKI_OTLP_PORT}/otlp
        tls:
          insecure: true
    service:
      telemetry:
        metrics:
          readers:
            - pull:
                exporter:
                  prometheus:
                    host: "0.0.0.0"
                    port: 8888
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [otlp/tempo, debug]
        metrics:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [prometheusremotewrite, prometheus]
        logs:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [otlphttp/loki, debug]
  mode: deployment
  replicas: 1
  image: otel/opentelemetry-collector-contrib:latest
EOF
)
        if echo "$COLLECTOR_CR_YAML" | kubectl apply -f - 2>&1; then
            if kubectl get opentelemetrycollector otel-collector -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
                echo_info "OpenTelemetryCollector instance created/updated successfully"
            else
                echo_info "OpenTelemetryCollector instance applied (may take a moment to appear)"
            fi
            echo "Waiting for OpenTelemetryCollector pods to be ready..."
            # Wait for collector pods to be created and ready
            set +e  # Temporarily disable exit on error
            for i in {1..60}; do
                if kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep -q Running; then
                    echo_info "OpenTelemetryCollector pods are running"
                    kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep Running || true
                    break
                fi
                if [ $i -eq 60 ]; then
                    echo_warn "OpenTelemetryCollector pods not ready after 2 minutes"
                    echo_warn "Checking status:"
                    kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null || true
                    kubectl get opentelemetrycollector otel-collector -n $OBSERVABILITY_NAMESPACE 2>/dev/null || true
                fi
                sleep 2
            done
            set -e  # Re-enable exit on error
        else
            echo_error "Failed to create/update OpenTelemetryCollector instance"
            echo_warn "Please check OTel Operator status:"
            echo_warn "  kubectl get pods -n opentelemetry-operator-system"
            echo_warn "  kubectl get crd opentelemetrycollectors.opentelemetry.io"
            echo_warn ""
            echo_warn "You can create it manually with the example shown in the output above"
        fi
    fi
fi

# Always ensure OpenTelemetryCollector CR exists (even if stack was already installed)
if [ "$OBSERVABILITY_INSTALLED" = "true" ] && [ "$OTEL_DEPLOYED" = "true" ]; then
    # Check if OTel Operator exists
    if kubectl get crd opentelemetrycollectors.opentelemetry.io >/dev/null 2>&1; then
        echo ""
        echo "Ensuring OpenTelemetryCollector CR exists (stack was already installed)..."
        if kubectl get opentelemetrycollector otel-collector -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
            echo_info "OpenTelemetryCollector instance already exists"
        else
            echo "Creating OpenTelemetryCollector instance..."
            # Get Tempo service name for exporter endpoint
            TEMPO_SVC_FOR_COLLECTOR="tempo"
            if ! kubectl get svc tempo -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
                TEMPO_SVC_FOR_COLLECTOR=$(kubectl get svc -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=tempo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "tempo")
            fi

            # Get Loki service URL for log export (Loki 3.0+ uses loki-gateway with OTLP support)
            LOKI_SVC_FOR_COLLECTOR=""
            LOKI_OTLP_PORT="80"
            if kubectl get svc loki-gateway -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
                LOKI_SVC_FOR_COLLECTOR="loki-gateway"
                LOKI_OTLP_PORT=$(kubectl get svc loki-gateway -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http-metrics")].port}' 2>/dev/null || echo "80")
            elif kubectl get svc -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=loki 2>/dev/null | grep -qi gateway; then
                LOKI_SVC_FOR_COLLECTOR=$(kubectl get svc -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=loki,app.kubernetes.io/component=gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            fi
            if [ -z "$LOKI_SVC_FOR_COLLECTOR" ]; then
                LOKI_SVC_FOR_COLLECTOR=$(kubectl get svc -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -iE "loki.*gateway|gateway.*loki" | head -1 | awk '{print $1}' || echo "")
            fi
            if [ -z "$LOKI_SVC_FOR_COLLECTOR" ] && kubectl get svc loki -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
                LOKI_SVC_FOR_COLLECTOR="loki"
            fi
            LOKI_SVC_FOR_COLLECTOR="${LOKI_SVC_FOR_COLLECTOR:-loki-gateway}"

            echo_info "Using Loki service for OTel Collector: $LOKI_SVC_FOR_COLLECTOR (OTLP port: $LOKI_OTLP_PORT)"

            # Create OpenTelemetryCollector CR for Loki 3.0+ with native OTLP support
            COLLECTOR_CR_YAML=$(cat <<EOF
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: ${OBSERVABILITY_NAMESPACE}
spec:
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      batch: {}
      resource:
        attributes:
          - key: job
            value: otel-collector
            action: upsert
          - key: service.name
            value: dm-nkp-gitops-custom-app
            action: upsert
    exporters:
      prometheusremotewrite:
        endpoint: http://prometheus-kube-prometheus-prometheus.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:9090/api/v1/write
      prometheus:
        endpoint: 0.0.0.0:8889
        metric_expiration: 180m
        enable_open_metrics: true
      debug:
        verbosity: detailed
      otlp/tempo:
        endpoint: ${TEMPO_SVC_FOR_COLLECTOR}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:4317
        tls:
          insecure: true
      otlphttp/loki:
        endpoint: http://${LOKI_SVC_FOR_COLLECTOR}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:${LOKI_OTLP_PORT}/otlp
        tls:
          insecure: true
    service:
      telemetry:
        metrics:
          readers:
            - pull:
                exporter:
                  prometheus:
                    host: "0.0.0.0"
                    port: 8888
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [otlp/tempo, debug]
        metrics:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [prometheusremotewrite, prometheus]
        logs:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [otlphttp/loki, debug]
  mode: deployment
  replicas: 1
  image: otel/opentelemetry-collector-contrib:latest
EOF
)
            if echo "$COLLECTOR_CR_YAML" | kubectl apply -f - 2>&1; then
                echo_info "OpenTelemetryCollector instance created successfully"
                # Wait for pods to be ready
                echo "Waiting for OpenTelemetryCollector pods to be ready..."
                set +e
                for i in {1..60}; do
                    if kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep -q Running; then
                        echo_info "OpenTelemetryCollector pods are running"
                        kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep Running || true
                        break
                    fi
                    sleep 2
                done
                set -e
            else
                echo_warn "Failed to create OpenTelemetryCollector instance"
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
    if run_with_timeout 15 kubectl wait --for=condition=ready pod "$OTEL_POD_NAME" -n $OBSERVABILITY_NAMESPACE --timeout=15s >/dev/null 2>&1; then
        echo_info "OTel Collector is ready: $OTEL_POD_NAME"
        OTEL_READY=true
    fi
fi

if [ "$OTEL_READY" = "false" ]; then
    # Try label-based selectors
    if run_with_timeout 15 kubectl wait --for=condition=ready pod -l component=otel-collector -n $OBSERVABILITY_NAMESPACE --timeout=15s >/dev/null 2>&1; then
        echo_info "OTel Collector is ready (component=otel-collector)"
        OTEL_READY=true
    elif run_with_timeout 15 kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=opentelemetry-collector -n $OBSERVABILITY_NAMESPACE --timeout=15s >/dev/null 2>&1; then
        echo_info "OTel Collector is ready (app.kubernetes.io/name=opentelemetry-collector)"
        OTEL_READY=true
    else
        echo_warn "OTel Collector may not be ready yet. Checking status..."
        kubectl get pods -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -i otel || echo_warn "No OTel Collector pods found"
        kubectl get deployment -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -i otel || echo_warn "No OTel Collector deployment found"
        echo_warn "OTel Collector is not ready, but continuing. Telemetry export may fail until it's ready."
    fi
fi

if run_with_timeout 15 kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n $OBSERVABILITY_NAMESPACE --timeout=15s >/dev/null 2>&1; then
    echo_info "Prometheus is ready"
else
    echo_warn "Prometheus may not be ready yet"
fi

if run_with_timeout 15 kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n $OBSERVABILITY_NAMESPACE --timeout=15s >/dev/null 2>&1; then
    echo_info "Grafana is ready"
else
    echo_warn "Grafana may not be ready yet"
fi

# Verify OTel Collector or Operator deployment
echo ""
echo_step "Verifying OTel deployment..."
OTEL_VERIFIED=false
OTEL_TYPE=""
OTEL_OPERATOR_RUNNING=false
OTEL_COLLECTOR_CR_EXISTS=false
OTEL_COLLECTOR_PODS_RUNNING=false

# Check if OTel Operator is installed (uses OpenTelemetryCollector CRD)
if kubectl get crd opentelemetrycollectors.opentelemetry.io >/dev/null 2>&1; then
    echo_info "OTel Operator detected (OpenTelemetryCollector CRD exists)"
    OTEL_TYPE="operator"
    # Check if OTel Operator is running (in opentelemetry-operator-system namespace)
    if kubectl get pods -n opentelemetry-operator-system -l app.kubernetes.io/name=opentelemetry-operator 2>/dev/null | grep -q Running; then
        echo_info "OTel Operator pods are running"
        kubectl get pods -n opentelemetry-operator-system -l app.kubernetes.io/name=opentelemetry-operator 2>/dev/null | grep Running || true
        OTEL_OPERATOR_RUNNING=true
        # Check if OpenTelemetryCollector instance exists
        if kubectl get opentelemetrycollector -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -v NAME | grep -q .; then
            echo_info "OpenTelemetryCollector instance(s) found"
            kubectl get opentelemetrycollector -n $OBSERVABILITY_NAMESPACE 2>/dev/null
            OTEL_COLLECTOR_CR_EXISTS=true
            # Check if collector pods are running (managed by operator)
            if kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep -q Running; then
                echo_info "OpenTelemetryCollector pods are running (managed by operator)"
                kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep Running || true
                OTEL_COLLECTOR_PODS_RUNNING=true
                OTEL_VERIFIED=true
            else
                echo_warn "OpenTelemetryCollector CR exists but pods are not running yet (may be starting up)"
            fi
        else
            echo_warn "OTel Operator is installed but no OpenTelemetryCollector instance found"
            echo_warn "The script should have created one above. Checking if creation failed..."
        fi
    else
        echo_warn "OTel Operator CRD exists but operator pods are not running"
    fi
fi

# Note: We only check for OTel Operator now (not direct Collector Helm chart)
# OTel Collector instances are managed by the Operator via OpenTelemetryCollector CR
# Check if OpenTelemetryCollector pods are running (created by operator)
if [ "$OTEL_VERIFIED" = "false" ] && [ "$OTEL_COLLECTOR_CR_EXISTS" = "true" ]; then
    if kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep -q Running; then
        echo_info "OpenTelemetryCollector pods are running (managed by operator)"
        kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator 2>/dev/null | grep Running || true
        OTEL_VERIFIED=true
    fi
fi

# Final check: Provide appropriate error messages based on what's missing
if [ "$OTEL_VERIFIED" = "false" ]; then
    echo ""
    if [ "$OTEL_OPERATOR_RUNNING" = "true" ] && [ "$OTEL_COLLECTOR_CR_EXISTS" = "false" ]; then
        echo_error "OpenTelemetryCollector CR instance not found!"
        echo_warn "OTel Operator is running, but no OpenTelemetryCollector CR exists."
        echo_warn "The script should have created one above. Please check the output above for errors."
        echo_warn "You can create it manually with the example shown below."
    elif [ "$OTEL_OPERATOR_RUNNING" = "true" ] && [ "$OTEL_COLLECTOR_CR_EXISTS" = "true" ] && [ "$OTEL_COLLECTOR_PODS_RUNNING" = "false" ]; then
        echo_error "OpenTelemetryCollector pods are not running!"
        echo_warn "OTel Operator is running and CR exists, but collector pods are not ready yet."
        echo_warn "This may be normal if the CR was just created - pods may take a minute to start."
        echo_warn "Check pod status: kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator"
    elif [ "$OTEL_OPERATOR_RUNNING" = "false" ]; then
        echo_error "OTel Operator not found or not running!"
        echo_warn "OTel Operator is required for metrics and traces."
    else
        echo_error "OTel Collector/Operator not found or not ready!"
        echo_warn "This will cause issues with telemetry export (metrics and traces will not work)."
    fi

    echo_warn "The application will still run, but metrics/traces export will fail."
    echo ""
    echo "Checking for any OTel-related resources..."
    kubectl get pods -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -iE "otel|opentelemetry" || echo_warn "  No OTel Collector pods found in $OBSERVABILITY_NAMESPACE namespace"
    kubectl get pods -n opentelemetry-operator-system 2>/dev/null | grep -iE "otel|opentelemetry" || echo_warn "  No OTel Operator pods found in opentelemetry-operator-system namespace"
    kubectl get svc -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -iE "otel|opentelemetry" || echo_warn "  No OTel services found"
    kubectl get opentelemetrycollector -n $OBSERVABILITY_NAMESPACE 2>/dev/null || echo_warn "  No OpenTelemetryCollector CR instances found"
fi

set -e  # Re-enable exit on error

if [ "$OTEL_VERIFIED" = "false" ]; then
    echo ""
    if [ "$OTEL_OPERATOR_RUNNING" = "true" ] && [ "$OTEL_COLLECTOR_CR_EXISTS" = "false" ]; then
        echo_warn "⚠️  WARNING: OpenTelemetryCollector CR instance not found"
        echo_warn "   OTel Operator is running, but no Collector CR exists."
        echo_warn "   The script should have created one above. Please check the output above for errors."
        echo_warn "   You can create it manually with the example shown below."
        echo_warn ""
        echo_warn "   kubectl apply -f - <<'EOF'"
        echo_warn "   apiVersion: opentelemetry.io/v1beta1"
        echo_warn "   kind: OpenTelemetryCollector"
        echo_warn "   metadata:"
        echo_warn "     name: otel-collector"
        echo_warn "     namespace: $OBSERVABILITY_NAMESPACE"
        echo_warn "   spec:"
        echo_warn "     config: |"
        echo_warn "       receivers:"
        echo_warn "         otlp:"
        echo_warn "           protocols:"
        echo_warn "             grpc:"
        echo_warn "               endpoint: 0.0.0.0:4317"
        echo_warn "       exporters:"
        echo_warn "         prometheusremotewrite:"
        echo_warn "           endpoint: http://prometheus-kube-prometheus-prometheus.$OBSERVABILITY_NAMESPACE.svc.cluster.local:9090/api/v1/write"
        echo_warn "       service:"
        echo_warn "         pipelines:"
        echo_warn "           metrics:"
        echo_warn "             receivers: [otlp]"
        echo_warn "             exporters: [prometheusremotewrite]"
        echo_warn "     mode: deployment"
        echo_warn "     replicas: 1"
        echo_warn "   'EOF'"
    elif [ "$OTEL_OPERATOR_RUNNING" = "true" ] && [ "$OTEL_COLLECTOR_CR_EXISTS" = "true" ] && [ "$OTEL_COLLECTOR_PODS_RUNNING" = "false" ]; then
        echo_warn "⚠️  WARNING: OpenTelemetryCollector pods are not running yet"
        echo_warn "   OTel Operator and CR exist, but collector pods are still starting."
        echo_warn "   This is normal if the CR was just created - wait a minute and check:"
        echo_warn "   kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator"
    else
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
    fi
    echo_warn ""
    echo_warn "   Continuing with deployment, but telemetry export will fail until Collector is ready..."
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
    run_with_timeout 15 kubectl wait --for condition=established --timeout=15s crd/gateways.gateway.networking.k8s.io >/dev/null 2>&1 || echo_warn "Gateway API CRDs may not be ready yet"
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
# Skip CRDs since Gateway API CRDs are already installed via kubectl
echo "Installing Traefik (this may take a few minutes)..."
if helm upgrade --install traefik traefik/traefik \
  --namespace $TRAEFIK_NAMESPACE \
  --set experimental.kubernetesGateway.enabled=true \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443 \
  --set service.type=NodePort \
  --skip-crds \
  --wait --timeout=2m 2>&1 | tee /tmp/traefik-install.log; then
    echo_info "Traefik with Gateway API support installed successfully"
else
    INSTALL_ERR=$(cat /tmp/traefik-install.log 2>/dev/null | tail -5)
    echo_warn "Traefik installation had issues, continuing..."
    echo_warn "Last few lines of install log:"
    echo_warn "$INSTALL_ERR"
fi

set -e  # Re-enable exit on error

# Wait for Traefik to be ready
echo "Waiting for Traefik to be ready..."
set +e  # Temporarily disable exit on error
if run_with_timeout 15 kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n $TRAEFIK_NAMESPACE --timeout=15s 2>&1; then
    echo_info "Traefik is ready"
else
    echo_warn "Traefik may not be ready yet, checking status..."
    kubectl get pods -n $TRAEFIK_NAMESPACE -l app.kubernetes.io/name=traefik 2>&1 || true
    kubectl describe pods -n $TRAEFIK_NAMESPACE -l app.kubernetes.io/name=traefik 2>&1 | tail -20 || true
    echo_warn "Continuing anyway..."
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

# Step 8b: Install MetalLB for LoadBalancer support (local testing)
echo ""
echo_step "Step 8b: Installing MetalLB for LoadBalancer support..."

METALLB_NAMESPACE="metallb-system"

# Check if MetalLB is already installed
if helm list -n $METALLB_NAMESPACE 2>/dev/null | grep -qE "^metallb[[:space:]]"; then
    echo_info "MetalLB already installed"
else
    # Detect Docker network subnet for kind cluster
    DOCKER_SUBNET=$(docker network inspect kind 2>/dev/null | jq -r '.[0].IPAM.Config[0].Subnet' 2>/dev/null || echo "")
    if [ -n "$DOCKER_SUBNET" ] && [ "$DOCKER_SUBNET" != "null" ]; then
        echo "Detected Docker network subnet: $DOCKER_SUBNET"
        # Calculate IP pool from Docker subnet (use last /24 for kind clusters)
        # Example: 172.18.0.0/16 -> 172.18.255.200-172.18.255.250
        IP_POOL_START="172.18.255.200"
        IP_POOL_END="172.18.255.250"

        # Try to extract base IP from subnet if possible
        if [[ "$DOCKER_SUBNET" =~ ^([0-9]+\.[0-9]+)\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            BASE_IP="${BASH_REMATCH[1]}"
            IP_POOL_START="${BASE_IP}.255.200"
            IP_POOL_END="${BASE_IP}.255.250"
        fi
        echo "Using IP pool: $IP_POOL_START-$IP_POOL_END"
    else
        # Default IP pool for kind clusters
        IP_POOL_START="172.18.255.200"
        IP_POOL_END="172.18.255.250"
        echo_warn "Could not detect Docker network subnet, using default IP pool: $IP_POOL_START-$IP_POOL_END"
    fi

    # Install MetalLB using official kubectl manifests (more reliable than Helm)
    echo "Installing MetalLB using official manifests..."

    # Create namespace
    kubectl create namespace $METALLB_NAMESPACE --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true

    METALLB_INSTALLED=true
    set +e  # Temporarily disable exit on error

    # Install MetalLB using official manifests
    if kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.6/config/manifests/metallb-native.yaml >/dev/null 2>&1; then
        echo_info "MetalLB manifests applied"

        # Wait for MetalLB pods to be ready
        echo "Waiting for MetalLB pods to be ready..."
        for i in {1..60}; do
            READY_PODS=$(kubectl get pods -n $METALLB_NAMESPACE -l app=metallb --no-headers 2>/dev/null | grep -c Running || echo "0")
            TOTAL_PODS=$(kubectl get pods -n $METALLB_NAMESPACE -l app=metallb --no-headers 2>/dev/null | wc -l | tr -d ' ')
            if [ "$READY_PODS" -ge 2 ] && [ "$READY_PODS" = "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
                echo_info "MetalLB pods are ready ($READY_PODS/$TOTAL_PODS)"
                break
            fi
            if [ $i -eq 60 ]; then
                echo_warn "MetalLB pods not ready after 2 minutes (may still be starting)"
            fi
            sleep 2
        done

        # Configure IP address pool
        echo "Configuring MetalLB IP address pool..."
        if kubectl apply -f - <<EOF >/dev/null 2>&1
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
        then
            echo_info "MetalLB IP address pool configured"
        else
            echo_warn "Failed to configure IP address pool, continuing..."
        fi
    else
        echo_warn "MetalLB installation failed, continuing with NodePort..."
        METALLB_INSTALLED=false
    fi
    set -e  # Re-enable exit on error

    # Wait for MetalLB to be ready
    if [ "$METALLB_INSTALLED" = "true" ]; then
        # MetalLB pods were already checked above, just verify they're still ready
        echo "Verifying MetalLB readiness..."
        set +e  # Temporarily disable exit on error
        READY_PODS=$(kubectl get pods -n $METALLB_NAMESPACE -l app=metallb --no-headers 2>/dev/null | grep -c Running || echo "0")
        if [ "$READY_PODS" -ge 2 ]; then
            echo_info "MetalLB is ready ($READY_PODS pods running)"
            METALLB_READY=true
        else
            echo_warn "MetalLB may not be fully ready yet ($READY_PODS pods running), but continuing..."
            METALLB_READY=false
        fi
        set -e  # Re-enable exit on error

        # Update Traefik service to LoadBalancer (if MetalLB is ready)
        if [ "$METALLB_READY" = "true" ]; then
            echo "Updating Traefik service to LoadBalancer type..."
            if kubectl patch svc traefik -n $TRAEFIK_NAMESPACE -p '{"spec":{"type":"LoadBalancer"}}' 2>&1; then
                echo_info "Traefik service updated to LoadBalancer"

                # Wait for LoadBalancer IP assignment
                echo "Waiting for LoadBalancer IP assignment..."
                for i in {1..30}; do
                    LB_IP=$(kubectl get svc traefik -n $TRAEFIK_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
                    if [ -n "$LB_IP" ]; then
                        echo_info "Traefik LoadBalancer IP assigned: $LB_IP"
                        break
                    fi
                    sleep 2
                done

                if [ -z "$LB_IP" ]; then
                    echo_warn "LoadBalancer IP not assigned yet (may take a moment)"
                    echo "You can check with: kubectl get svc traefik -n $TRAEFIK_NAMESPACE"
                fi
            else
                echo_warn "Failed to update Traefik service to LoadBalancer, continuing with NodePort..."
            fi
        fi
    fi
fi

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

# Detect Loki and Tempo services for datasource URLs (before Helm deployment)
echo ""
echo "Detecting Loki and Tempo services for Grafana datasource configuration..."
LOKI_SVC=""
LOKI_PORT=""
LOKI_URL=""
set +e  # Temporarily disable exit on error
# Try different service name patterns for Loki
if kubectl get svc -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=loki 2>/dev/null | grep -qi gateway; then
    LOKI_SVC=$(kubectl get svc -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=loki,app.kubernetes.io/component=gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
               kubectl get svc -n $OBSERVABILITY_NAMESPACE 2>/dev/null | grep -iE "loki.*gateway|gateway.*loki" | head -1 | awk '{print $1}')
    if [ -n "$LOKI_SVC" ]; then
        LOKI_PORT=$(kubectl get svc "$LOKI_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null)
        if [ -z "$LOKI_PORT" ]; then
            LOKI_PORT=$(kubectl get svc "$LOKI_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")
        fi
    fi
elif kubectl get svc loki-gateway -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
    LOKI_SVC="loki-gateway"
    LOKI_PORT=$(kubectl get svc "$LOKI_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http-metrics")].port}' 2>/dev/null || echo "80")
elif kubectl get svc loki-loki-distributed-gateway -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
    LOKI_SVC="loki-loki-distributed-gateway"
    LOKI_PORT=$(kubectl get svc "$LOKI_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null || echo "80")
elif kubectl get svc loki -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
    LOKI_SVC="loki"
    LOKI_PORT=$(kubectl get svc "$LOKI_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "3100")
fi

if [ -n "$LOKI_SVC" ] && [ -n "$LOKI_PORT" ]; then
    LOKI_URL="http://${LOKI_SVC}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:${LOKI_PORT}"
    echo_info "Found Loki service: $LOKI_SVC (port: $LOKI_PORT)"
else
    echo_warn "Loki service not found, using default URL"
    LOKI_URL="http://loki-gateway.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:80"
fi
set -e  # Re-enable exit on error

TEMPO_SVC=""
TEMPO_PORT=""
TEMPO_URL=""
set +e  # Temporarily disable exit on error
# Try different service name patterns for Tempo
if kubectl get svc tempo -n $OBSERVABILITY_NAMESPACE >/dev/null 2>&1; then
    TEMPO_SVC="tempo"
    TEMPO_PORT=$(kubectl get svc "$TEMPO_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null)
    if [ -z "$TEMPO_PORT" ]; then
        TEMPO_PORT=$(kubectl get svc "$TEMPO_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "3200")
    fi
elif kubectl get svc -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=tempo 2>/dev/null | grep -q tempo; then
    TEMPO_SVC=$(kubectl get svc -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=tempo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$TEMPO_SVC" ]; then
        TEMPO_PORT=$(kubectl get svc "$TEMPO_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null)
        if [ -z "$TEMPO_PORT" ]; then
            TEMPO_PORT=$(kubectl get svc "$TEMPO_SVC" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "3200")
        fi
    fi
fi

if [ -n "$TEMPO_SVC" ] && [ -n "$TEMPO_PORT" ]; then
    TEMPO_URL="http://${TEMPO_SVC}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:${TEMPO_PORT}"
    echo_info "Found Tempo service: $TEMPO_SVC (port: $TEMPO_PORT)"
else
    echo_warn "Tempo service not found, using default URL"
    TEMPO_URL="http://tempo.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:3200"
fi
set -e  # Re-enable exit on error

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
    # Ensure dashboards are deployed to observability namespace where Grafana is
    # Helm upgrade will update existing resources including dashboards
    # Enable datasources via ConfigMap (persistent, survives restarts)
    HELM_CMD="helm upgrade --install $APP_NAME chart/dm-nkp-gitops-custom-app \
      --namespace $APP_NAMESPACE \
      --create-namespace \
      -f chart/dm-nkp-gitops-custom-app/values-local-testing.yaml \
      --set image.repository=$IMAGE_REPO \
      --set image.tag=$IMAGE_TAG \
      --set image.pullPolicy=Never \
      --set tls.enabled=false \
      --set tls.clusterIssuer.create=false \
      --set tls.certificate.create=false \
      --set grafana.dashboards.enabled=true \
      --set grafana.dashboards.namespace=$OBSERVABILITY_NAMESPACE \
      --set grafana.datasources.enabled=true \
      --set grafana.datasources.namespace=$OBSERVABILITY_NAMESPACE \
      --set grafana.datasources.loki.url=\"$LOKI_URL\" \
      --set grafana.datasources.tempo.url=\"$TEMPO_URL\" \
      --set grafana.datasources.prometheus.url=\"http://prometheus-kube-prometheus-prometheus.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:9090\""

    # Enable Gateway API if detected
    if [ "$ENABLE_GATEWAY" = "true" ]; then
        HELM_CMD="$HELM_CMD --set gateway.enabled=true"
        echo "  Gateway API: enabled"
    else
        echo "  Gateway API: disabled (not detected)"
    fi

    HELM_CMD="$HELM_CMD --wait --timeout=2m"

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
if run_with_timeout 15 kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=$APP_NAME -n $APP_NAMESPACE --timeout=15s >/dev/null 2>&1; then
    echo_info "Application pods are ready (app.kubernetes.io/name=$APP_NAME)"
    APP_READY=true
elif run_with_timeout 15 kubectl wait --for=condition=ready pod -l app=$APP_NAME -n $APP_NAMESPACE --timeout=15s >/dev/null 2>&1; then
    echo_info "Application pods are ready (app=$APP_NAME)"
    APP_READY=true
elif run_with_timeout 15 kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=$APP_NAME -n $APP_NAMESPACE --timeout=15s >/dev/null 2>&1; then
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

# Verify Grafana dashboards are deployed
echo ""
echo_step "Verifying Grafana dashboards deployment..."
DASHBOARD_CONFIGMAPS=$(kubectl get configmap -n $OBSERVABILITY_NAMESPACE -l grafana_dashboard=1 2>/dev/null | grep -c dashboard || echo "0")
if [ "$DASHBOARD_CONFIGMAPS" -gt 0 ]; then
    echo_info "Found $DASHBOARD_CONFIGMAPS Grafana dashboard ConfigMap(s) in $OBSERVABILITY_NAMESPACE namespace"
    kubectl get configmap -n $OBSERVABILITY_NAMESPACE -l grafana_dashboard=1 2>/dev/null | grep dashboard || true
    echo ""
    echo "Note: kube-prometheus-stack should auto-discover dashboards from ConfigMaps with label grafana_dashboard=1"
    echo "If dashboards don't appear in Grafana UI, check Grafana configuration:"
    echo "  kubectl get configmap -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/name=grafana -o yaml | grep -A 20 dashboards"

    # Verify dashboard ConfigMaps have the correct structure
    echo ""
    echo "Verifying dashboard ConfigMap structure..."
    for CM_NAME in $(kubectl get configmap -n $OBSERVABILITY_NAMESPACE -l grafana_dashboard=1 -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        if kubectl get configmap "$CM_NAME" -n $OBSERVABILITY_NAMESPACE -o jsonpath='{.data}' 2>/dev/null | grep -q "dashboard"; then
            echo_info "  ✓ $CM_NAME has dashboard data"
        else
            echo_warn "  ⚠ $CM_NAME may be missing dashboard data"
        fi
    done
else
    echo_warn "No Grafana dashboards ConfigMaps found in $OBSERVABILITY_NAMESPACE namespace"
    echo_warn "Dashboards should be deployed by Helm chart. Checking Helm release..."
    if helm get manifest $APP_NAME -n $APP_NAMESPACE 2>/dev/null | grep -qi "grafana.*dashboard"; then
        echo_warn "  Dashboard resources found in Helm manifest but ConfigMaps not created"
        echo_warn "  This may be a namespace mismatch. Checking..."
        # Check if dashboards were deployed to wrong namespace
        WRONG_NS_DASHBOARDS=$(kubectl get configmap -A -l grafana_dashboard=1 2>/dev/null | grep -c dashboard || echo "0")
        if [ "$WRONG_NS_DASHBOARDS" -gt 0 ]; then
            echo_warn "  Found dashboards in other namespaces:"
            kubectl get configmap -A -l grafana_dashboard=1 2>/dev/null | grep dashboard || true
            echo_warn "  Consider moving them to $OBSERVABILITY_NAMESPACE namespace"
        fi
    else
        echo_warn "  No dashboard resources in Helm manifest"
        echo_warn "  Ensure grafana.dashboards.enabled=true in values"
    fi
fi

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

# Step 11: Create and Verify Grafana datasources
echo ""
echo_step "Step 11: Creating Grafana datasources..."

# Wait for Grafana to be ready
echo "Waiting for Grafana to be ready..."
set +e  # Temporarily disable exit on error
for i in {1..30}; do
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n $OBSERVABILITY_NAMESPACE --timeout=5s >/dev/null 2>&1; then
        echo_info "Grafana is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo_warn "Grafana may not be fully ready yet, continuing anyway..."
    fi
    sleep 2
done
set -e  # Re-enable exit on error

# Get Grafana credentials
GRAFANA_PASSWORD=$(kubectl get secret -n $OBSERVABILITY_NAMESPACE prometheus-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")

# Create datasources directly via Grafana API (most reliable method)
echo "Creating datasources via Grafana API (reliable method)..."

# Start port-forward to Grafana in background
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana 3000:80 >/dev/null 2>&1 &
PF_PID=$!
sleep 3

# Check if port-forward is working
set +e  # Temporarily disable exit on error
if ! kill -0 $PF_PID 2>/dev/null; then
    echo_warn "Port-forward failed, retrying..."
    kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana 3000:80 >/dev/null 2>&1 &
    PF_PID=$!
    sleep 3
fi

GRAFANA_URL="http://localhost:3000"
GRAFANA_AUTH="admin:${GRAFANA_PASSWORD}"

# Function to create or update a datasource
create_datasource() {
    local name="$1"
    local type="$2"
    local url="$3"
    local uid="$4"
    local is_default="${5:-false}"
    local json_data="${6:-{}}"

    # Check if datasource already exists
    EXISTING=$(curl -s -u "$GRAFANA_AUTH" "$GRAFANA_URL/api/datasources/name/$name" 2>/dev/null)
    if echo "$EXISTING" | grep -q '"id"'; then
        echo "  Datasource '$name' already exists, updating..."
        DS_ID=$(echo "$EXISTING" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
        curl -s -X PUT -u "$GRAFANA_AUTH" -H "Content-Type: application/json" \
            "$GRAFANA_URL/api/datasources/$DS_ID" \
            -d "{
                \"id\": $DS_ID,
                \"name\": \"$name\",
                \"type\": \"$type\",
                \"url\": \"$url\",
                \"uid\": \"$uid\",
                \"access\": \"proxy\",
                \"isDefault\": $is_default,
                \"jsonData\": $json_data
            }" >/dev/null 2>&1
        echo_info "  Updated datasource: $name"
    else
        echo "  Creating datasource: $name..."
        RESULT=$(curl -s -X POST -u "$GRAFANA_AUTH" -H "Content-Type: application/json" \
            "$GRAFANA_URL/api/datasources" \
            -d "{
                \"name\": \"$name\",
                \"type\": \"$type\",
                \"url\": \"$url\",
                \"uid\": \"$uid\",
                \"access\": \"proxy\",
                \"isDefault\": $is_default,
                \"jsonData\": $json_data
            }" 2>/dev/null)
        if echo "$RESULT" | grep -q '"id"'; then
            echo_info "  Created datasource: $name"
        elif echo "$RESULT" | grep -q "already exists"; then
            echo_info "  Datasource '$name' already exists"
        else
            echo_warn "  Failed to create datasource '$name': $RESULT"
        fi
    fi
}

# Determine service URLs (use detected values or defaults)
PROMETHEUS_URL="http://prometheus-kube-prometheus-prometheus.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:9090"

# Use detected LOKI_URL or fall back to default (Loki 3.0+ uses loki-gateway)
if [ -z "$LOKI_URL" ]; then
    LOKI_URL="http://loki-gateway.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:80"
fi

# Use detected TEMPO_URL or fall back to default
if [ -z "$TEMPO_URL" ]; then
    TEMPO_URL="http://tempo.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:3200"
fi

echo "Using datasource URLs:"
echo "  Prometheus: $PROMETHEUS_URL"
echo "  Loki: $LOKI_URL"
echo "  Tempo: $TEMPO_URL"

# Create Prometheus datasource (default)
create_datasource "Prometheus" "prometheus" "$PROMETHEUS_URL" "prometheus" "true" '{"httpMethod":"POST","timeInterval":"15s"}'

# Create Loki datasource with derivedFields for trace correlation
LOKI_JSON_DATA='{
    "maxLines": 1000,
    "derivedFields": [
        {
            "datasourceUid": "tempo",
            "matcherRegex": "traceID=(\\w+)",
            "name": "TraceID",
            "url": "${__value.raw}"
        }
    ]
}'
create_datasource "Loki" "loki" "$LOKI_URL" "loki" "false" "$LOKI_JSON_DATA"

# Create Tempo datasource with trace-to-logs and trace-to-metrics correlation
TEMPO_JSON_DATA='{
    "httpMethod": "GET",
    "serviceMap": {"datasourceUid": "prometheus"},
    "nodeGraph": {"enabled": true},
    "search": {"hide": false},
    "tracesToLogs": {
        "datasourceUid": "loki",
        "tags": ["job", "instance", "pod", "namespace"],
        "spanStartTimeShift": "1h",
        "spanEndTimeShift": "1h",
        "filterByTraceID": false,
        "filterBySpanID": false
    },
    "tracesToMetrics": {
        "datasourceUid": "prometheus",
        "tags": [{"key": "service.name", "value": "service"}, {"key": "job"}]
    }
}'
create_datasource "Tempo" "tempo" "$TEMPO_URL" "tempo" "false" "$TEMPO_JSON_DATA"

# Stop port-forward
kill $PF_PID 2>/dev/null || true
set -e  # Re-enable exit on error

# Verify datasources were created
echo ""
echo "Verifying datasources..."
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-grafana 3000:80 >/dev/null 2>&1 &
PF_PID=$!
sleep 2

set +e
DS_COUNT=$(curl -s -u "$GRAFANA_AUTH" "$GRAFANA_URL/api/datasources" 2>/dev/null | grep -o '"name"' | wc -l | tr -d ' ')
if [ "$DS_COUNT" -ge 3 ]; then
    echo_info "Successfully verified $DS_COUNT datasources in Grafana"
    curl -s -u "$GRAFANA_AUTH" "$GRAFANA_URL/api/datasources" 2>/dev/null | grep -o '"name":"[^"]*"' | sed 's/"name":"//g; s/"//g' | while read ds; do
        echo "  ✅ $ds"
    done
else
    echo_warn "Could not verify all datasources (found: $DS_COUNT). They may still be provisioning."
    echo "  You can check manually: curl -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/datasources"
fi
kill $PF_PID 2>/dev/null || true
set -e

# Note: Dashboards are provisioned via Helm chart ConfigMaps (persistent)
echo ""
echo "Dashboards are provisioned via Helm chart ConfigMaps (persistent, survives restarts)"
echo "  Dashboard ConfigMaps are deployed by Helm chart with label grafana_dashboard=1"
echo "  Grafana will auto-discover them (sidecar.dashboards.enabled=true was set)"

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
echo "  4. Data sources configured via Grafana API (persistent):"
echo "     ✅ Prometheus: http://prometheus-kube-prometheus-prometheus.$OBSERVABILITY_NAMESPACE.svc.cluster.local:9090"
echo "     ✅ Loki: ${LOKI_URL:-http://loki-gateway.$OBSERVABILITY_NAMESPACE.svc.cluster.local:80}"
echo "     ✅ Tempo: ${TEMPO_URL:-http://tempo.$OBSERVABILITY_NAMESPACE.svc.cluster.local:3200}"
echo "     (Verify datasources: curl -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/datasources)"
echo ""
echo "  5. View dashboards:"
echo "     - Application dashboards are provisioned via Helm chart ConfigMaps (persistent)"
echo "     - Dashboards auto-discover from ConfigMaps with label grafana_dashboard=1"
echo "     - Check dashboards: kubectl get configmap -n $OBSERVABILITY_NAMESPACE -l grafana_dashboard=1"
echo "     - Available dashboards:"
echo "       * Metrics Dashboard (dashboard-metrics.json)"
echo "       * Logs Dashboard (dashboard-logs.json)"
echo "       * Traces Dashboard (dashboard-traces.json)"
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
echo "📝 Log Collection:"
echo "  - OTLP logs: Application → OTel Collector (deployment) → Loki"
echo "  - stdout/stderr logs: Pods → Logging Operator → Fluent Bit/D → Loki"
echo ""
echo "  View application logs:"
echo "    kubectl logs -n $APP_NAMESPACE -l app.kubernetes.io/name=$APP_NAME --tail=50"
echo ""
echo "  Check Logging Operator:"
echo "    kubectl get pods -n logging"
echo "    kubectl get logging,output,flow -n logging"
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

    # Check if MetalLB is installed and Traefik has LoadBalancer IP
    TRAEFIK_SVC_TYPE=$(kubectl get svc traefik -n traefik-system -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
    TRAEFIK_LB_IP=$(kubectl get svc traefik -n traefik-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [ "$TRAEFIK_SVC_TYPE" = "LoadBalancer" ] && [ -n "$TRAEFIK_LB_IP" ]; then
        echo "    ✅ MetalLB LoadBalancer IP assigned: $TRAEFIK_LB_IP"
        echo ""
        echo "    1. Add hostname to /etc/hosts (one-time setup):"
        echo "       echo \"$TRAEFIK_LB_IP dm-nkp-gitops-custom-app.local\" | sudo tee -a /etc/hosts"
        echo ""
        echo "    2. Access application via LoadBalancer IP and hostname:"
        echo "       curl http://dm-nkp-gitops-custom-app.local/"
        echo "       curl http://dm-nkp-gitops-custom-app.local/health"
        echo "       curl http://dm-nkp-gitops-custom-app.local/ready"
        echo ""
        echo "       Or directly via LoadBalancer IP:"
        echo "       curl -H \"Host: dm-nkp-gitops-custom-app.local\" http://$TRAEFIK_LB_IP/"
    elif [ "$TRAEFIK_SVC_TYPE" = "LoadBalancer" ]; then
        echo "    ✅ MetalLB installed - Traefik service is LoadBalancer type"
        echo "    ⚠️  LoadBalancer IP not assigned yet (may take a moment)"
        echo "    Check with: kubectl get svc traefik -n traefik-system"
        echo ""
        echo "    Fallback: Use port-forward until IP is assigned"
        echo "       kubectl port-forward -n traefik-system svc/traefik 8080:80"
    else
        echo "    ⚠️  Traefik is using NodePort (MetalLB may not be installed)"
        echo ""
        echo "    1. Port forward to Traefik Gateway:"
        echo "       kubectl port-forward -n traefik-system svc/traefik 8080:80"
        echo ""
        echo "    2. Add hostname to /etc/hosts (one-time setup):"
        echo "       echo \"127.0.0.1 dm-nkp-gitops-custom-app.local\" | sudo tee -a /etc/hosts"
        echo ""
        echo "    3. Access application via hostname:"
        echo "       curl http://dm-nkp-gitops-custom-app.local/"
        echo ""
        echo "    Or use NodePort directly:"
        echo "      NODE_IP=\$(docker inspect ${CLUSTER_NAME}-control-plane --format='{{.NetworkSettings.Networks.kind.IPAddress}}' 2>/dev/null || echo \"localhost\")"
        echo "      curl -H \"Host: dm-nkp-gitops-custom-app.local\" http://\${NODE_IP}:30080/"
    fi

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
