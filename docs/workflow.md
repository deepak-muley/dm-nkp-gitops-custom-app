# End-to-End Workflow

This document describes the complete workflow from development to deployment.

## Development Workflow

### 1. Local Development

```bash
# Clone repository
git clone https://github.com/deepak-muley/dm-nkp-gitops-custom-app.git
cd dm-nkp-gitops-custom-app

# Install dependencies
make deps

# Build application
make build

# Run locally
./bin/dm-nkp-gitops-custom-app
```

### 2. Testing

```bash
# Run all tests
make test

# Run specific test types
make unit-tests
make integration-tests
make e2e-tests
```

### 3. Code Quality

```bash
# Format code
make fmt

# Run linters
make lint
```

## CI/CD Workflow

### Continuous Integration (CI)

Triggered on:
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop`

Steps:
1. Checkout code
2. Setup Go environment
3. Download dependencies
4. Run linters
5. Run unit tests
6. Run integration tests
7. Run e2e tests (with kind)
8. Build application
9. Package Helm chart

See: `.github/workflows/ci.yml`

### Continuous Deployment (CD)

Triggered on:
- Tags matching `v*` pattern
- Push to `main` branch

Steps:
1. Extract version from tag or use default
2. Build Docker image using buildpacks
3. Push image to `ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:VERSION`
4. Package Helm chart
5. Push Helm chart to OCI registry

See: `.github/workflows/cd.yml`

## Container Build Workflow

### Using Buildpacks (Recommended)

```bash
# Install pack CLI
# macOS: brew install buildpacks/tap/pack
# Linux: See https://buildpacks.io/docs/tools/pack/

# Build image
make docker-build

# Build and push
export GITHUB_TOKEN=your_token
make docker-push
```

### Using Dockerfile (Alternative)

```bash
docker build -t ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0 .
docker push ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0
```

## Helm Chart Workflow

### Package Chart

```bash
make helm-chart
```

Creates: `chart/dm-nkp-gitops-custom-app-0.1.0.tgz`

### Push to OCI Registry

```bash
export GITHUB_TOKEN=your_token
make push-helm-chart
```

Pushes to: `oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app`

### Install from OCI Registry

```bash
helm install dm-nkp-gitops-custom-app \
  oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app \
  --version 0.1.0
```

## Deployment Workflow

### Option 1: Helm Chart

```bash
# Install
helm install dm-nkp-gitops-custom-app \
  oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app \
  --version 0.1.0 \
  --namespace default

# Upgrade
helm upgrade dm-nkp-gitops-custom-app \
  oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app \
  --version 0.2.0
```

### Option 2: Kubernetes Manifests

```bash
# Deploy base resources
kubectl apply -f manifests/base/

# Deploy Traefik IngressRoute
kubectl apply -f manifests/traefik/

# Or deploy Gateway API HTTPRoute
export APP_NAME=dm-nkp-gitops-custom-app
export NAMESPACE=default
export GATEWAY_NAME=traefik
export GATEWAY_NAMESPACE=traefik-system
export HOSTNAME=dm-nkp-gitops-custom-app.local
export HTTP_PORT=8080
export METRICS_PORT=9090

envsubst < manifests/gateway-api/httproute-template.yaml | kubectl apply -f -
```

### Option 3: Using Script

```bash
export APP_NAME=dm-nkp-gitops-custom-app
export NAMESPACE=default
export GATEWAY_NAME=traefik
export GATEWAY_NAMESPACE=traefik-system
export HOSTNAME=dm-nkp-gitops-custom-app.local

./scripts/deploy.sh
```

## Integration with Nutanix NKP

### Prerequisites

- Nutanix NKP cluster with:
  - Prometheus Operator
  - Grafana
  - Traefik or Gateway API
  - Loki (optional)
  - Dex (optional)

### Deployment Steps

1. **Deploy Application**:
   ```bash
   helm install dm-nkp-gitops-custom-app \
     oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app \
     --version 0.1.0
   ```

2. **Verify ServiceMonitor** (for Prometheus):
   ```bash
   kubectl get servicemonitor
   ```

3. **Configure Ingress** (Traefik or Gateway API):
   ```bash
   kubectl apply -f manifests/traefik/
   # or
   kubectl apply -f manifests/gateway-api/
   ```

4. **Verify Metrics Scraping**:
   - Check Prometheus targets
   - Verify metrics in Grafana

5. **Create Grafana Dashboard**:
   - Import dashboard from `docs/grafana-dashboard.json` (if available)
   - Or create custom dashboard using metrics from `docs/metrics.md`

## Release Workflow

1. **Update Version**:
   - Update `VERSION` in `Makefile`
   - Update `version` in `chart/dm-nkp-gitops-custom-app/Chart.yaml`
   - Update `appVersion` in `chart/dm-nkp-gitops-custom-app/Chart.yaml`

2. **Create Tag**:
   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

3. **GitHub Actions**:
   - CD workflow automatically builds and pushes image
   - CD workflow automatically packages and pushes Helm chart

4. **Verify Release**:
   ```bash
   # Check image
   docker pull ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0

   # Check Helm chart
   helm show chart oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app --version 0.1.0
   ```

## Troubleshooting

### Build Issues

- Ensure Go 1.25+ is installed
- Run `make deps` to update dependencies
- Clear build cache: `make clean`

### Test Issues

- Check required tools: `kind`, `kubectl`, `curl`
- Verify ports 8080/9090 are available
- Check firewall settings

### Deployment Issues

- Verify Kubernetes cluster access: `kubectl cluster-info`
- Check image pull secrets
- Verify Helm chart syntax: `helm lint chart/dm-nkp-gitops-custom-app`

### CI/CD Issues

- Check GitHub Actions logs
- Verify secrets are set (GITHUB_TOKEN)
- Check OCI registry permissions

