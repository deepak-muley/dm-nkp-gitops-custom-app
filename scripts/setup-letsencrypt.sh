#!/bin/bash
set -euo pipefail

# Script to set up Let's Encrypt with cert-manager for Gateway API
# Usage: ./scripts/setup-letsencrypt.sh [email] [environment]
#   email: Your email for Let's Encrypt notifications (required for production)
#   environment: staging or prod (default: staging)

ACME_EMAIL="${1:-admin@example.com}"
ENVIRONMENT="${2:-staging}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.14.0}"
TRAEFIK_NAMESPACE="${TRAEFIK_NAMESPACE:-traefik-system}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }
echo_step() { echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${GREEN}  $1${NC}"; echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

echo "=========================================="
echo "  Let's Encrypt Setup with cert-manager"
echo "=========================================="
echo ""
echo "Email: $ACME_EMAIL"
echo "Environment: $ENVIRONMENT"
echo "cert-manager version: $CERT_MANAGER_VERSION"
echo ""

# Check prerequisites
command -v helm >/dev/null 2>&1 || { echo_error "helm is required but not installed. Aborting."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo_error "kubectl is required but not installed. Aborting."; exit 1; }

# Validate environment
if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "prod" ]]; then
    echo_error "Environment must be 'staging' or 'prod'"
    exit 1
fi

# Warn about email for production
if [[ "$ENVIRONMENT" == "prod" && "$ACME_EMAIL" == "admin@example.com" ]]; then
    echo_warn "Using default email for production. Consider providing your real email:"
    echo_warn "  ./scripts/setup-letsencrypt.sh your-email@example.com prod"
    echo ""
    read -p "Continue with default email? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ============================================================================
# Step 1: Install cert-manager
# ============================================================================
echo_step "Step 1: Installing cert-manager"

# Add Helm repo
echo_info "Adding cert-manager Helm repository..."
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update

# Check if cert-manager is already installed
if helm status cert-manager -n cert-manager >/dev/null 2>&1; then
    echo_info "cert-manager is already installed. Checking version..."
    INSTALLED_VERSION=$(helm get metadata cert-manager -n cert-manager -o json 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    echo_info "Installed version: $INSTALLED_VERSION"

    read -p "Upgrade cert-manager? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        helm upgrade cert-manager jetstack/cert-manager \
            --namespace cert-manager \
            --version "$CERT_MANAGER_VERSION" \
            --set installCRDs=true \
            --set "extraArgs={--feature-gates=ExperimentalGatewayAPISupport=true}" \
            --wait --timeout=5m
    fi
else
    echo_info "Installing cert-manager..."
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version "$CERT_MANAGER_VERSION" \
        --set installCRDs=true \
        --set "extraArgs={--feature-gates=ExperimentalGatewayAPISupport=true}" \
        --wait --timeout=5m
fi

# Wait for cert-manager to be ready
echo_info "Waiting for cert-manager pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=5m

echo_success "cert-manager installed successfully"

# ============================================================================
# Step 2: Create ClusterIssuer
# ============================================================================
echo_step "Step 2: Creating Let's Encrypt ClusterIssuers"

# Determine ACME server based on environment
if [[ "$ENVIRONMENT" == "prod" ]]; then
    ACME_SERVER="https://acme-v02.api.letsencrypt.org/directory"
    ISSUER_NAME="letsencrypt-prod"
else
    ACME_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
    ISSUER_NAME="letsencrypt-staging"
fi

echo_info "Creating ClusterIssuer: $ISSUER_NAME"

# Create ClusterIssuer with HTTP-01 challenge for Gateway API
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${ACME_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
    - http01:
        gatewayHTTPRoute:
          parentRefs:
            - name: traefik
              namespace: ${TRAEFIK_NAMESPACE}
              kind: Gateway
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${ACME_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        gatewayHTTPRoute:
          parentRefs:
            - name: traefik
              namespace: ${TRAEFIK_NAMESPACE}
              kind: Gateway
EOF

# Wait for ClusterIssuer to be ready
echo_info "Waiting for ClusterIssuer to be ready..."
for i in {1..30}; do
    if kubectl get clusterissuer "$ISSUER_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True; then
        echo_success "ClusterIssuer $ISSUER_NAME is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo_warn "ClusterIssuer may not be ready yet. Check status with:"
        echo_warn "  kubectl describe clusterissuer $ISSUER_NAME"
    fi
    sleep 2
done

# ============================================================================
# Step 3: Update Gateway with HTTPS listener
# ============================================================================
echo_step "Step 3: Updating Gateway with HTTPS listener"

# Check if Gateway exists
if kubectl get gateway traefik -n "$TRAEFIK_NAMESPACE" >/dev/null 2>&1; then
    echo_info "Gateway 'traefik' found. Updating with HTTPS listener..."

    # Apply updated Gateway with HTTPS listener
    cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: traefik
  namespace: ${TRAEFIK_NAMESPACE}
  annotations:
    cert-manager.io/cluster-issuer: "${ISSUER_NAME}"
spec:
  gatewayClassName: traefik
  listeners:
    - name: web
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
    - name: websecure
      protocol: HTTPS
      port: 443
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - name: gateway-tls-cert
            kind: Secret
EOF
    echo_success "Gateway updated with HTTPS listener"
else
    echo_warn "Gateway 'traefik' not found in namespace $TRAEFIK_NAMESPACE"
    echo_info "Creating new Gateway with HTTP and HTTPS listeners..."

    cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: traefik
  namespace: ${TRAEFIK_NAMESPACE}
  annotations:
    cert-manager.io/cluster-issuer: "${ISSUER_NAME}"
spec:
  gatewayClassName: traefik
  listeners:
    - name: web
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
    - name: websecure
      protocol: HTTPS
      port: 443
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - name: gateway-tls-cert
            kind: Secret
EOF
    echo_success "Gateway created with HTTP and HTTPS listeners"
fi

# ============================================================================
# Step 4: Create Certificate
# ============================================================================
echo_step "Step 4: Creating TLS Certificate"

# Get hostnames from existing HTTPRoutes
HOSTNAMES=$(kubectl get httproute -A -o jsonpath='{.items[*].spec.hostnames[*]}' 2>/dev/null | tr ' ' '\n' | sort -u | grep -v '^$' || echo "dm-nkp-gitops-custom-app.local")

echo_info "Found hostnames: $HOSTNAMES"

# Build dnsNames array
DNS_NAMES=""
for hostname in $HOSTNAMES; do
    DNS_NAMES="$DNS_NAMES    - $hostname
"
done

# Default if no hostnames found
if [ -z "$DNS_NAMES" ]; then
    DNS_NAMES="    - dm-nkp-gitops-custom-app.local
    - observability.local"
fi

# Create Certificate
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: gateway-tls-cert
  namespace: ${TRAEFIK_NAMESPACE}
spec:
  secretName: gateway-tls-cert
  duration: 2160h    # 90 days
  renewBefore: 360h  # Renew 15 days before expiry
  issuerRef:
    name: ${ISSUER_NAME}
    kind: ClusterIssuer
    group: cert-manager.io
  commonName: dm-nkp-gitops-custom-app.local
  dnsNames:
${DNS_NAMES}
  privateKey:
    algorithm: RSA
    size: 2048
    rotationPolicy: Always
  usages:
    - server auth
    - client auth
EOF

echo_success "Certificate created"

# ============================================================================
# Step 5: Update Traefik Service (ensure port 443 is exposed)
# ============================================================================
echo_step "Step 5: Ensuring Traefik service exposes port 443"

# Check current Traefik service
TRAEFIK_SVC_TYPE=$(kubectl get svc traefik -n "$TRAEFIK_NAMESPACE" -o jsonpath='{.spec.type}' 2>/dev/null || echo "")

if [ -n "$TRAEFIK_SVC_TYPE" ]; then
    echo_info "Traefik service type: $TRAEFIK_SVC_TYPE"

    # Check if port 443 exists
    HTTPS_PORT=$(kubectl get svc traefik -n "$TRAEFIK_NAMESPACE" -o jsonpath='{.spec.ports[?(@.port==443)].port}' 2>/dev/null || echo "")

    if [ -z "$HTTPS_PORT" ]; then
        echo_info "Port 443 not found. Adding HTTPS port to service..."
        kubectl patch svc traefik -n "$TRAEFIK_NAMESPACE" --type='json' \
            -p='[{"op": "add", "path": "/spec/ports/-", "value": {"port": 443, "targetPort": "websecure", "protocol": "TCP", "name": "websecure"}}]' || {
            echo_warn "Could not patch service. Port 443 may already exist or use different config."
        }
    else
        echo_success "Port 443 already configured on Traefik service"
    fi

    # If LoadBalancer, show IP
    if [ "$TRAEFIK_SVC_TYPE" == "LoadBalancer" ]; then
        LB_IP=$(kubectl get svc traefik -n "$TRAEFIK_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [ -n "$LB_IP" ]; then
            echo_success "LoadBalancer IP: $LB_IP"
        else
            echo_warn "LoadBalancer IP not assigned yet"
        fi
    fi
else
    echo_warn "Traefik service not found in namespace $TRAEFIK_NAMESPACE"
fi

# ============================================================================
# Step 6: Verification
# ============================================================================
echo_step "Step 6: Verification"

echo_info "Checking cert-manager pods..."
kubectl get pods -n cert-manager

echo ""
echo_info "Checking ClusterIssuers..."
kubectl get clusterissuers

echo ""
echo_info "Checking Certificates..."
kubectl get certificates -A

echo ""
echo_info "Checking Gateway..."
kubectl get gateway -n "$TRAEFIK_NAMESPACE" -o wide

echo ""
echo_info "Checking Traefik service..."
kubectl get svc traefik -n "$TRAEFIK_NAMESPACE"

# ============================================================================
# Summary
# ============================================================================
echo_step "Setup Complete!"

echo "📋 Summary:"
echo "   - cert-manager: Installed ($CERT_MANAGER_VERSION)"
echo "   - ClusterIssuers: letsencrypt-staging, letsencrypt-prod"
echo "   - Active Issuer: $ISSUER_NAME"
echo "   - Gateway: Updated with HTTPS listener (port 443)"
echo "   - Certificate: gateway-tls-cert"
echo ""

# Get LoadBalancer IP
LB_IP=$(kubectl get svc traefik -n "$TRAEFIK_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -n "$LB_IP" ]; then
    echo "🌐 Access your services:"
    echo "   HTTP:  http://$LB_IP"
    echo "   HTTPS: https://$LB_IP"
    echo ""
    echo "   Add to /etc/hosts:"
    echo "   $LB_IP dm-nkp-gitops-custom-app.local observability.local"
    echo ""
    echo "   Then access:"
    echo "   https://dm-nkp-gitops-custom-app.local"
    echo "   https://observability.local/grafana/"
else
    echo "🔧 Next steps:"
    echo "   1. Ensure MetalLB or cloud LoadBalancer is configured"
    echo "   2. Wait for LoadBalancer IP assignment"
    echo "   3. Configure DNS or /etc/hosts to point to LoadBalancer IP"
fi

echo ""
echo "🔍 Troubleshooting commands:"
echo "   kubectl describe certificate gateway-tls-cert -n $TRAEFIK_NAMESPACE"
echo "   kubectl describe clusterissuer $ISSUER_NAME"
echo "   kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager"
echo ""

if [[ "$ENVIRONMENT" == "staging" ]]; then
    echo_warn "Using staging Let's Encrypt. Certificates will show as untrusted in browsers."
    echo_warn "For production, run: ./scripts/setup-letsencrypt.sh your-email@example.com prod"
fi

echo ""
echo_success "Let's Encrypt setup complete!"
