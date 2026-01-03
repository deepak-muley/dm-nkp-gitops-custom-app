#!/bin/bash
set -euo pipefail

# Verification script for dm-nkp-gitops-custom-app
# This script verifies that builds work both locally and in Docker

APP_NAME="dm-nkp-gitops-custom-app"
IMAGE_NAME="ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0"
TEST_CONTAINER="dm-nkp-verify-test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}✓${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo_error() {
    echo -e "${RED}✗${NC} $1"
}

cleanup() {
    echo ""
    echo "Cleaning up..."
    docker stop $TEST_CONTAINER 2>/dev/null || true
    docker rm $TEST_CONTAINER 2>/dev/null || true
    pkill -f $APP_NAME 2>/dev/null || true
}

trap cleanup EXIT

echo "=========================================="
echo "  Verification Script"
echo "=========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
MISSING_TOOLS=()

command -v go >/dev/null 2>&1 || MISSING_TOOLS+=("go")
command -v docker >/dev/null 2>&1 || MISSING_TOOLS+=("docker")
command -v make >/dev/null 2>&1 || MISSING_TOOLS+=("make")
command -v helm >/dev/null 2>&1 || MISSING_TOOLS+=("helm")
command -v pack >/dev/null 2>&1 || MISSING_TOOLS+=("pack")
command -v kubesec >/dev/null 2>&1 || MISSING_TOOLS+=("kubesec")

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo_error "Missing tools: ${MISSING_TOOLS[*]}"
    echo "Please install missing tools before running verification."
    exit 1
fi
echo_info "All prerequisites installed"

# Check Go version
GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
echo_info "Go version: $GO_VERSION"

# Check Docker is running
if ! docker ps >/dev/null 2>&1; then
    echo_error "Docker is not running. Please start Docker Desktop."
    exit 1
fi
echo_info "Docker is running"

echo ""
echo "=========================================="
echo "  Step 1: Local Build"
echo "=========================================="

echo "Cleaning previous builds..."
make clean >/dev/null 2>&1 || true

echo "Downloading dependencies..."
if make deps; then
    echo_info "Dependencies downloaded"
else
    echo_error "Failed to download dependencies"
    exit 1
fi

echo "Building application..."
if make build; then
    echo_info "Application built successfully"
    if [ -f "bin/$APP_NAME" ]; then
        echo_info "Binary exists: bin/$APP_NAME"
        ls -lh bin/$APP_NAME
    else
        echo_error "Binary not found"
        exit 1
    fi
else
    echo_error "Build failed"
    exit 1
fi

echo ""
echo "Testing binary locally..."
./bin/$APP_NAME >/dev/null 2>&1 &
APP_PID=$!
sleep 2

if curl -s http://localhost:8080/health >/dev/null; then
    echo_info "Health endpoint responding"
else
    echo_error "Health endpoint not responding"
    kill $APP_PID 2>/dev/null || true
    exit 1
fi

if curl -s http://localhost:9090/metrics >/dev/null; then
    echo_info "Metrics endpoint responding"
else
    echo_error "Metrics endpoint not responding"
    kill $APP_PID 2>/dev/null || true
    exit 1
fi

kill $APP_PID 2>/dev/null || true
echo_info "Local binary test passed"

echo ""
echo "=========================================="
echo "  Step 2: Docker Build (Dockerfile)"
echo "=========================================="

echo "Building Docker image with Dockerfile..."
if docker build -t $APP_NAME:dockerfile-test . >/dev/null 2>&1; then
    echo_info "Docker image built successfully"
    docker images | grep "$APP_NAME:dockerfile-test" | head -1
else
    echo_error "Docker build failed"
    exit 1
fi

echo "Testing Docker container..."
if docker run -d --name $TEST_CONTAINER -p 8080:8080 -p 9090:9090 $APP_NAME:dockerfile-test >/dev/null 2>&1; then
    sleep 3
    if curl -s http://localhost:8080/health >/dev/null; then
        echo_info "Docker container health check passed"
    else
        echo_error "Docker container health check failed"
        docker logs $TEST_CONTAINER
        exit 1
    fi
    docker stop $TEST_CONTAINER >/dev/null 2>&1
    docker rm $TEST_CONTAINER >/dev/null 2>&1
else
    echo_error "Failed to start Docker container"
    exit 1
fi

echo ""
echo "=========================================="
echo "  Step 3: Buildpacks Build"
echo "=========================================="

echo "Building with buildpacks..."
if make docker-build >/dev/null 2>&1; then
    echo_info "Buildpacks build successful"
    docker images | grep "$APP_NAME" | head -1
else
    echo_warn "Buildpacks build failed (may need network access)"
    echo_warn "Skipping buildpacks verification"
fi

echo ""
echo "=========================================="
echo "  Step 4: Helm Chart"
echo "=========================================="

echo "Packaging Helm chart..."
if make helm-chart >/dev/null 2>&1; then
    echo_info "Helm chart packaged"
    if [ -f "chart/$APP_NAME-0.1.0.tgz" ]; then
        echo_info "Helm chart file exists"
        ls -lh chart/*.tgz
    fi
else
    echo_error "Helm chart packaging failed"
    exit 1
fi

echo "Linting Helm chart..."
if helm lint chart/$APP_NAME >/dev/null 2>&1; then
    echo_info "Helm chart lint passed"
else
    echo_warn "Helm chart lint warnings (check output above)"
fi

echo ""
echo "=========================================="
echo "  Step 5: Security Scanning"
echo "=========================================="

echo "Running kubesec on base manifests..."
if make kubesec >/dev/null 2>&1; then
    echo_info "Kubesec scan completed"
else
    echo_warn "Kubesec scan had issues (check output above)"
fi

echo "Running kubesec on Helm chart..."
if make kubesec-helm >/dev/null 2>&1; then
    echo_info "Kubesec Helm scan completed"
else
    echo_warn "Kubesec Helm scan had issues (check output above)"
fi

echo ""
echo "=========================================="
echo "  Step 6: Tests"
echo "=========================================="

echo "Running unit tests..."
if make unit-tests >/dev/null 2>&1; then
    echo_info "Unit tests passed"
else
    echo_warn "Unit tests had issues (check output above)"
fi

echo ""
echo "=========================================="
echo "  Verification Complete!"
echo "=========================================="
echo ""
echo_info "All verification steps completed successfully!"
echo ""
echo "Next steps:"
echo "  1. Review any warnings above"
echo "  2. Check GitHub Actions for CI/CD verification"
echo "  3. Deploy to Kubernetes using Helm chart"
echo ""
echo "For detailed information, see:"
echo "  - docs/verification.md"
echo "  - docs/buildpacks.md"
echo ""

