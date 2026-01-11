# Running End-to-End Tests

## Quick Start

### Option 1: Using Makefile (Recommended)

```bash
make e2e-tests
```

This will:
- Check for required tools (kind, curl)
- Run all E2E tests in `tests/e2e/` with the `e2e` build tag
- Timeout after 30 minutes

### Option 2: Using Automated Demo Script

For a complete end-to-end demo including observability stack:

```bash
./scripts/run-e2e-demo.sh
```

This script will:
1. Build the application
2. Run unit tests
3. Build Docker image
4. Create kind cluster
5. Load image into kind
6. Deploy application
7. Deploy observability stack (OTel Collector, Prometheus, Loki, Tempo, Grafana)
8. Deploy Grafana dashboards
9. Generate traffic
10. Provide instructions to access Grafana

### Option 3: Manual Go Test

```bash
go test -v -tags=e2e -timeout=30m ./tests/e2e/...
```

## Prerequisites

### Required Tools

- **Go** 1.25+
- **kind** - Kubernetes in Docker: https://kind.sigs.k8s.io/
- **kubectl** - Kubernetes CLI: https://kubernetes.io/docs/tasks/tools/
- **helm** - Package manager: https://helm.sh/
- **curl** - For making HTTP requests
- **Docker** - Running and accessible

### Optional Tools

- **jq** - For JSON processing (used by some scripts)

### Installing Prerequisites

**macOS (using Homebrew)**:
```bash
brew install kind kubectl helm jq
```

**Linux**:
```bash
# kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## E2E Test with OpenTelemetry Observability Stack

### Step 1: Deploy Observability Stack (LOCAL TESTING ONLY)

```bash
# Deploy observability stack for local testing
./scripts/setup-observability-stack.sh

# Or manually:
helm install observability-stack ./chart/observability-stack \
  --namespace observability \
  --create-namespace \
  --wait
```

### Step 2: Deploy Application with Dashboards

```bash
# Deploy application with local testing values
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  -f ./chart/dm-nkp-gitops-custom-app/values-local-testing.yaml

# Wait for application to be ready
kubectl wait --for=condition=ready pod -l app=dm-nkp-gitops-custom-app --timeout=2m
```

### Step 3: Generate Traffic

```bash
# Port-forward to application
kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080 &

# Generate traffic
for i in {1..50}; do
  curl http://localhost:8080/
  curl http://localhost:8080/health
  curl http://localhost:8080/ready
  sleep 0.5
done
```

### Step 4: Run E2E Tests

```bash
# Run E2E tests
make e2e-tests

# Or directly:
go test -v -tags=e2e -timeout=30m ./tests/e2e/...
```

### Step 5: Verify in Grafana

```bash
# Port-forward to Grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80

# Access Grafana
open http://localhost:3000
# Login: admin/admin

# Navigate to: Dashboards → Browse
# Should see:
#   - dm-nkp-gitops-custom-app - Metrics
#   - dm-nkp-gitops-custom-app - Logs
#   - dm-nkp-gitops-custom-app - Traces
```

## What the E2E Tests Cover

The E2E tests in `tests/e2e/e2e_test.go` verify:

1. **Local Application Tests**:
   - Application starts and responds to health checks
   - HTTP endpoints return correct responses
   - Metrics are generated (if `/metrics` endpoint exists)

2. **Kubernetes Deployment Tests**:
   - Application deploys successfully on kind cluster
   - Pods become ready
   - Services are accessible
   - Application responds to requests

3. **Observability Tests** (with OpenTelemetry):
   - OTel Collector receives telemetry data
   - Prometheus scrapes metrics from OTel Collector
   - Logs are exported to Loki (via OTel Collector)
   - Traces are exported to Tempo (via OTel Collector)
   - Grafana is accessible
   - Grafana dashboards are deployed

## Troubleshooting

### E2E Tests Fail with "kind not installed"

```bash
# Install kind
brew install kind  # macOS
# or
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### E2E Tests Fail with "kind cluster not found"

```bash
# Create kind cluster
kind create cluster --name dm-nkp-test-cluster

# Or let the tests create it automatically
```

### E2E Tests Timeout

- Increase timeout: `go test -v -tags=e2e -timeout=60m ./tests/e2e/...`
- Check if resources are sufficient: `kubectl top nodes`
- Verify pods are ready: `kubectl get pods --all-namespaces`

### Application Pods Not Ready

```bash
# Check pod status
kubectl get pods -l app=dm-nkp-gitops-custom-app

# Check logs
kubectl logs -l app=dm-nkp-gitops-custom-app

# Check events
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

### Observability Stack Not Working

```bash
# Check OTel Collector
kubectl get pods -n observability -l component=otel-collector
kubectl logs -n observability -l component=otel-collector

# Check Prometheus
kubectl get pods -n observability -l app.kubernetes.io/name=prometheus
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open: http://localhost:9090/targets

# Check Grafana
kubectl get pods -n observability -l app.kubernetes.io/name=grafana
kubectl logs -n observability -l app.kubernetes.io/name=grafana
```

## Cleanup

### Clean Up After E2E Tests

```bash
# Delete kind cluster
kind delete cluster --name dm-nkp-test-cluster

# Or delete specific resources
kubectl delete deployment dm-nkp-gitops-custom-app
kubectl delete service dm-nkp-gitops-custom-app
kubectl delete namespace observability
```

### Clean Up Observability Stack

```bash
# Uninstall observability stack
helm uninstall observability-stack -n observability

# Or delete namespace
kubectl delete namespace observability
```

## Summary

**Quick Command**:
```bash
make e2e-tests
```

**Full E2E Demo with Observability**:
```bash
./scripts/run-e2e-demo.sh
```

**Manual Steps**:
1. Deploy observability stack: `./scripts/setup-observability-stack.sh`
2. Deploy application: `helm install app ./chart/dm-nkp-gitops-custom-app -f values-local-testing.yaml`
3. Run tests: `make e2e-tests`
4. Verify in Grafana: `kubectl port-forward -n observability svc/prometheus-grafana 3000:80`
