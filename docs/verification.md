# Verification Guide

This guide provides step-by-step instructions to verify that the application builds correctly both locally and in Docker, and that CI/CD processes work locally.

## Prerequisites

Before running verification steps, ensure you have the following installed:

```bash
# Check Go version (should be 1.25+)
go version

# Check Docker
docker --version

# Check Make
make --version

# Check Helm (for Helm chart verification)
helm version

# Check kubesec (for security scanning)
kubesec version

# Check pack CLI (for buildpacks)
pack version
```

### Installing Missing Tools

```bash
# Install Go (if needed)
brew install go

# Install Docker Desktop (if needed)
# Download from https://www.docker.com/products/docker-desktop

# Install Helm
brew install helm

# Install kubesec
brew install kubesec

# Install pack CLI (for buildpacks)
brew install buildpacks/tap/pack
```

## Step 1: Verify Local Build

### 1.1 Clean and Prepare

```bash
# Navigate to project directory
cd /Users/deepak/go/src/github.com/deepak-muley/dm-nkp-gitops-custom-app

# Clean previous builds
make clean

# Download dependencies
make deps
```

### 1.2 Build Application

```bash
# Build the application
make build

# Verify binary was created
ls -lh bin/dm-nkp-gitops-custom-app

# Check binary information
file bin/dm-nkp-gitops-custom-app
```

### 1.3 Test the Binary Locally

```bash
# Run the application
./bin/dm-nkp-gitops-custom-app

# In another terminal, test endpoints:
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:9090/metrics

# Stop the application (Ctrl+C in the first terminal)
```

### 1.4 Run Tests

```bash
# Run all unit tests
make unit-tests

# Run integration tests
make integration-tests

# Run all tests
make test
```

## Step 2: Verify Docker Build (Traditional Dockerfile)

### 2.1 Build Docker Image

```bash
# Build using Dockerfile
docker build -t dm-nkp-gitops-custom-app:test .

# Verify image was created
docker images | grep dm-nkp-gitops-custom-app
```

### 2.2 Test Docker Container

```bash
# Run the container
docker run -d \
  --name dm-nkp-test \
  -p 8080:8080 \
  -p 9090:9090 \
  dm-nkp-gitops-custom-app:test

# Wait a few seconds for startup
sleep 3

# Test endpoints
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:9090/metrics

# Check container logs
docker logs dm-nkp-test

# Stop and remove container
docker stop dm-nkp-test
docker rm dm-nkp-test
```

### 2.3 Verify Container Security

```bash
# Check container runs as non-root
docker run --rm dm-nkp-gitops-custom-app:test id

# Should show: uid=65532(nonroot) gid=65532(nonroot)
```

## Step 3: Verify Buildpacks Build

### 3.1 Build with Buildpacks

```bash
# Build using buildpacks (recommended method)
make docker-build

# Or manually:
pack build dm-nkp-gitops-custom-app:test \
  --builder gcr.io/buildpacks/builder:google-22 \
  --env GOOGLE_RUNTIME_VERSION=1.25 \
  --env GOOGLE_BUILDABLE=./cmd/app \
  --env PORT=8080 \
  --env METRICS_PORT=9090
```

### 3.2 Test Buildpacks Container

```bash
# Run the buildpacks container
docker run -d \
  --name dm-nkp-pack-test \
  -p 8080:8080 \
  -p 9090:9090 \
  dm-nkp-gitops-custom-app:test

# Test endpoints
curl http://localhost:8080/
curl http://localhost:9090/metrics

# Check logs
docker logs dm-nkp-pack-test

# Cleanup
docker stop dm-nkp-pack-test
docker rm dm-nkp-pack-test
```

### 3.3 Compare Image Sizes

```bash
# Compare Dockerfile vs Buildpacks image sizes
docker images | grep dm-nkp-gitops-custom-app

# Buildpacks images are typically smaller and more secure
```

## Step 4: Verify Helm Chart

### 4.1 Package Helm Chart

```bash
# Package the Helm chart
make helm-chart

# Verify chart was created
ls -lh chart/*.tgz
```

### 4.2 Lint Helm Chart

```bash
# Lint the Helm chart
helm lint chart/dm-nkp-gitops-custom-app

# Should show: "1 chart(s) linted, 0 failures"
```

### 4.3 Render and Verify Helm Templates

```bash
# Render Helm templates
helm template test-release chart/dm-nkp-gitops-custom-app > /tmp/rendered.yaml

# Verify rendered output
cat /tmp/rendered.yaml

# Check for security settings
grep -A 5 "securityContext" /tmp/rendered.yaml
grep -A 3 "readOnlyRootFilesystem" /tmp/rendered.yaml
```

### 4.4 Test Helm Chart with Dry Run

```bash
# Test installation (dry-run)
helm install test-release chart/dm-nkp-gitops-custom-app --dry-run --debug

# Should show all resources that would be created
```

## Step 5: Verify Security Scanning

### 5.1 Run Kubesec on Base Manifests

```bash
# Scan base Kubernetes manifests
make kubesec

# Review the security score
# Should show high scores for all security checks
```

### 5.2 Run Kubesec on Helm Chart

```bash
# Scan rendered Helm chart
make kubesec-helm

# Verify security score is 9/9 or close to it
```

## Step 6: Verify CI/CD Locally

### 6.1 Simulate CI Workflow

```bash
# Run all CI steps locally
make clean
make deps
make lint
make build
make test
make helm-chart
make kubesec
make kubesec-helm
```

### 6.2 Test GitHub Actions Locally (Optional)

If you have `act` installed (GitHub Actions local runner):

```bash
# Install act
brew install act

# Run CI workflow locally
act push

# Run specific job
act -j test
act -j kubesec
```

### 6.3 Verify All Makefile Targets

```bash
# Show all available targets
make help

# Test each target individually
make deps
make fmt
make vet
make lint
make build
make unit-tests
make integration-tests
make clean
make helm-chart
make kubesec
make kubesec-helm
```

## Step 7: End-to-End Verification

### 7.1 Complete Build and Deploy Test

```bash
# 1. Clean everything
make clean

# 2. Download dependencies
make deps

# 3. Run linters
make lint

# 4. Build application
make build

# 5. Run tests
make test

# 6. Build Docker image (buildpacks)
make docker-build

# 7. Package Helm chart
make helm-chart

# 8. Security scan
make kubesec
make kubesec-helm

# 9. Test the built image
docker run -d --name test-app -p 8080:8080 -p 9090:9090 \
  ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0

# 10. Verify endpoints
curl http://localhost:8080/health
curl http://localhost:9090/metrics

# 11. Cleanup
docker stop test-app && docker rm test-app
```

## Troubleshooting

### Build Fails

```bash
# Check Go version
go version  # Should be 1.25+

# Clean and rebuild
make clean
make deps
make build
```

### Docker Build Fails

```bash
# Check Docker is running
docker ps

# Check Dockerfile syntax
docker build --no-cache -t test .

# Check buildpacks
pack builder suggest
```

### Helm Chart Issues

```bash
# Validate Helm chart
helm lint chart/dm-nkp-gitops-custom-app

# Check template rendering
helm template test chart/dm-nkp-gitops-custom-app --debug
```

### Kubesec Issues

```bash
# Verify kubesec is installed
kubesec version

# Test with a simple manifest
echo 'apiVersion: v1\nkind: Pod' | kubesec scan -
```

## Expected Results

After completing all verification steps, you should have:

✅ Binary built successfully (`bin/dm-nkp-gitops-custom-app`)  
✅ Docker image built (both Dockerfile and buildpacks)  
✅ All tests passing  
✅ Helm chart packaged  
✅ Security scans showing high scores (9/9)  
✅ Application running and responding to requests  
✅ Metrics endpoint accessible  

## Next Steps

Once verification is complete:

1. **Commit changes**: `git add . && git commit -m "Add security hardening"`
2. **Push to GitHub**: `git push origin main`
3. **Verify GitHub Actions**: Check Actions tab in GitHub
4. **Deploy to Kubernetes**: Use Helm chart or manifests

