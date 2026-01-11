# Running End-to-End Tests Locally - Final Command

## Quick Answer: Final Command

**The final command to run end-to-end tests locally:**

```bash
make e2e-tests
```

This is the **recommended** command. It runs comprehensive e2e tests with OpenTelemetry observability stack.

---

## What This Command Does

```bash
make e2e-tests
```

**Prerequisites Check**:
- ✅ Verifies `kind` is installed
- ✅ Verifies `curl` is installed

**What It Runs**:
- ✅ Builds the application
- ✅ Creates kind cluster
- ✅ Deploys OpenTelemetry observability stack (OTel Collector, Prometheus, Loki, Tempo, Grafana)
- ✅ Deploys application with OTel configuration
- ✅ Runs all e2e tests in `tests/e2e/e2e_test.go`
- ✅ Verifies metrics, logs, and traces collection
- ✅ Timeout: 30 minutes

**Command Details**:
```bash
go test -v -tags=e2e -timeout=30m ./tests/e2e/...
```

---

## Alternative: Interactive Demo Script

If you want an **interactive demo** with step-by-step output:

```bash
./scripts/e2e-demo-otel.sh
```

**What It Does**:
- ✅ Builds and tests application
- ✅ Creates kind cluster
- ✅ Deploys complete observability stack
- ✅ Deploys application with OpenTelemetry
- ✅ Generates traffic to create telemetry data
- ✅ Provides instructions to access Grafana dashboards
- ✅ Keeps cluster running for inspection

**Difference**: This script provides more interactive feedback and instructions, while `make e2e-tests` is for automated testing.

---

## Prerequisites

Before running e2e tests, ensure you have:

```bash
# Required tools
go version          # Go 1.25+
docker --version    # Docker running
kind version        # kind installed
kubectl version     # kubectl installed
helm version        # Helm 3.x
curl --version      # curl installed

# Optional but recommended
make --version      # Make (for make e2e-tests)
```

**Install on macOS**:
```bash
brew install kind kubectl helm
```

**Install on Linux**:
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

---

## Complete E2E Test Workflow

### Step 1: Ensure Prerequisites

```bash
# Verify all tools
make e2e-tests  # This will check prerequisites automatically
```

### Step 2: Run E2E Tests

```bash
# Automated e2e tests (RECOMMENDED)
make e2e-tests
```

**What happens**:
1. Checks prerequisites (kind, curl)
2. Builds application
3. Creates kind cluster (if needed)
4. Deploys observability stack
5. Deploys application with OTel
6. Runs all e2e tests
7. Verifies telemetry collection

### Step 3: Access Grafana (After Tests)

```bash
# Port forward to Grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80

# Open browser
open http://localhost:3000
# Login: admin/admin
```

---

## What Gets Tested

The e2e tests verify:

### ✅ Application Deployment
- Application deploys successfully
- Pods become ready
- Services are accessible
- Application responds to requests

### ✅ OpenTelemetry Integration
- OTel Collector receives telemetry
- Metrics exported via OTLP
- Logs exported via OTLP
- Traces exported via OTLP

### ✅ Observability Stack
- Prometheus scrapes metrics from OTel Collector
- Loki receives logs (via OTel Collector)
- Tempo receives traces (via OTel Collector)
- Grafana is accessible
- Grafana data sources configured

### ✅ Telemetry Flow
- Application → OTel Collector → Prometheus/Loki/Tempo
- Metrics visible in Prometheus
- Logs visible in Loki
- Traces visible in Tempo
- All data accessible in Grafana

---

## Troubleshooting

### E2E Tests Fail: "kind not installed"

```bash
# Install kind
brew install kind  # macOS
# or
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### E2E Tests Fail: "kind cluster not found"

```bash
# Create kind cluster manually (if needed)
kind create cluster --name dm-nkp-test-cluster

# Or let the tests create it automatically
```

### E2E Tests Timeout

```bash
# Increase timeout (if needed)
go test -v -tags=e2e -timeout=60m ./tests/e2e/...

# Check if resources are sufficient
kubectl top nodes

# Verify pods are ready
kubectl get pods --all-namespaces
```

### Application Pods Not Ready

```bash
# Check pod status
kubectl get pods -l app=dm-nkp-gitops-custom-app

# Check logs
kubectl logs -l app=dm-nkp-gitops-custom-app

# Check events
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

### OTel Collector Not Receiving Telemetry

```bash
# Check OTel Collector pods
kubectl get pods -n observability -l component=otel-collector

# Check OTel Collector logs
kubectl logs -n observability -l component=otel-collector --tail=50

# Verify application can reach OTel Collector
kubectl exec -it deployment/dm-nkp-gitops-custom-app -- \
  nc -zv otel-collector.observability.svc.cluster.local 4317
```

---

## Cleanup

After running e2e tests:

```bash
# Delete kind cluster (if you want to clean up)
kind delete cluster --name dm-nkp-test-cluster

# Or keep cluster for inspection (cluster is kept by default)
```

---

## Summary

**Final Command for Local E2E Testing**:

```bash
make e2e-tests
```

**Alternative for Interactive Demo**:

```bash
./scripts/e2e-demo-otel.sh
```

**Both commands**:
- ✅ Deploy OpenTelemetry observability stack
- ✅ Deploy application with OTel configuration
- ✅ Test complete telemetry pipeline
- ✅ Verify metrics, logs, and traces

**Difference**:
- `make e2e-tests`: Automated testing (recommended)
- `./scripts/e2e-demo-otel.sh`: Interactive demo with instructions

---

## Related Documentation

- [docs/RUNNING_E2E_TESTS.md](RUNNING_E2E_TESTS.md) - Detailed e2e testing guide
- [docs/E2E_TESTING_UPDATE.md](E2E_TESTING_UPDATE.md) - E2E testing status and updates
- [docs/E2E_DEMO.md](E2E_DEMO.md) - Step-by-step demo guide
- [docs/OPENTELEMETRY_QUICK_START.md](OPENTELEMETRY_QUICK_START.md) - Quick start guide
- [docs/opentelemetry-workflow.md](opentelemetry-workflow.md) - Complete OpenTelemetry workflow
