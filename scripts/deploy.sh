#!/bin/bash
set -euo pipefail

# Deployment script using envsubst

APP_NAME="${APP_NAME:-dm-nkp-gitops-custom-app}"
NAMESPACE="${NAMESPACE:-default}"
GATEWAY_NAME="${GATEWAY_NAME:-traefik}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-traefik-system}"
HOSTNAME="${HOSTNAME:-dm-nkp-gitops-custom-app.local}"
HTTP_PORT="${HTTP_PORT:-8080}"
METRICS_PORT="${METRICS_PORT:-9090}"

echo "Deploying ${APP_NAME} to namespace ${NAMESPACE}..."

# Deploy base resources
echo "Deploying base resources..."
kubectl apply -f manifests/base/

# Deploy Gateway API HTTPRoute if template exists
if [ -f "manifests/gateway-api/httproute-template.yaml" ]; then
    echo "Deploying Gateway API HTTPRoute..."
    envsubst < manifests/gateway-api/httproute-template.yaml | kubectl apply -f -
fi

echo "Deployment complete!"
echo "Application available at: http://${HOSTNAME}"
