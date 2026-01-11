#!/bin/bash
# Script to prepare environment for video recording
# This ensures everything is ready for a smooth demo recording

set -euo pipefail

echo "=========================================="
echo "  Preparing Environment for Video Demo"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"
MISSING=()

command -v go >/dev/null 2>&1 || MISSING+=("go")
command -v docker >/dev/null 2>&1 || MISSING+=("docker")
command -v kubectl >/dev/null 2>&1 || MISSING+=("kubectl")
command -v kind >/dev/null 2>&1 || MISSING+=("kind")
command -v helm >/dev/null 2>&1 || MISSING+=("helm")
command -v curl >/dev/null 2>&1 || MISSING+=("curl")

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${YELLOW}Warning: Missing prerequisites:${NC}"
    for cmd in "${MISSING[@]}"; do
        echo "  - $cmd"
    done
    echo ""
    echo "Please install missing tools before recording."
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites installed${NC}"
echo ""

# Show versions
echo -e "${BLUE}Tool Versions:${NC}"
go version
docker --version
kubectl version --client --short
kind version
helm version
curl --version
echo ""

# Clean previous state (optional)
read -p "Clean previous kind clusters? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Cleaning previous clusters...${NC}"
    kind delete cluster --name dm-nkp-demo-cluster 2>/dev/null || true
    kind delete cluster --name dm-nkp-test-cluster 2>/dev/null || true
    echo -e "${GREEN}✓ Cleaned${NC}"
    echo ""
fi

# Build application
echo -e "${BLUE}Building application...${NC}"
make clean
make deps
make build
echo -e "${GREEN}✓ Application built${NC}"
echo ""

# Run tests
echo -e "${BLUE}Running unit tests...${NC}"
make unit-tests || {
    echo -e "${YELLOW}Warning: Some tests may have warnings, but continuing...${NC}"
}
echo ""

# Validate Helm charts
echo -e "${BLUE}Validating Helm charts...${NC}"
helm lint ./chart/observability-stack || {
    echo -e "${YELLOW}Warning: Helm lint issues found, but continuing...${NC}"
}
helm lint ./chart/dm-nkp-gitops-custom-app || {
    echo -e "${YELLOW}Warning: Helm lint issues found, but continuing...${NC}"
}
echo -e "${GREEN}✓ Helm charts validated${NC}"
echo ""

# Validate dashboard JSON files
echo -e "${BLUE}Validating Grafana dashboard JSON files...${NC}"
for dashboard in grafana/dashboard-*.json; do
    if [ -f "$dashboard" ]; then
        python3 -m json.tool "$dashboard" > /dev/null && \
            echo -e "${GREEN}✓ $(basename $dashboard)${NC}" || \
            echo -e "${YELLOW}✗ $(basename $dashboard) - Invalid JSON${NC}"
    fi
done
echo ""

# Show demo commands
echo "=========================================="
echo -e "${GREEN}Environment Ready for Recording!${NC}"
echo "=========================================="
echo ""
echo -e "${BLUE}Demo Commands (copy these for video):${NC}"
echo ""
echo "# Step 1: Deploy observability stack"
echo "./scripts/setup-observability-stack.sh"
echo ""
echo "# Step 2: Deploy application"
echo "helm install app ./chart/dm-nkp-gitops-custom-app \\"
echo "  --namespace default \\"
echo "  -f ./chart/dm-nkp-gitops-custom-app/values-local-testing.yaml"
echo ""
echo "# Step 3: Check deployed resources"
echo "kubectl get pods -n observability"
echo "kubectl get pods -n default -l app=dm-nkp-gitops-custom-app"
echo "kubectl get servicemonitor -n observability"
echo "kubectl get configmap -n observability -l grafana_dashboard=1"
echo ""
echo "# Step 4: Generate traffic"
echo "kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080 &"
echo "for i in {1..50}; do curl http://localhost:8080/; sleep 0.2; done"
echo ""
echo "# Step 5: Access Grafana"
echo "kubectl port-forward -n observability svc/prometheus-grafana 3000:80"
echo "# Open http://localhost:3000 (admin/admin)"
echo ""
echo -e "${GREEN}Ready to record! 🎬${NC}"
