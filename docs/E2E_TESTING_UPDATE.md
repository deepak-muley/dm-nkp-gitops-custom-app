# End-to-End Testing - Current Status & Recommendations

## Current Status

### ✅ UP TO DATE

1. **`make e2e-tests`** (Recommended)
   - **Status**: ✅ UP TO DATE
   - **Location**: Makefile target
   - **What it does**: Runs Go tests in `tests/e2e/e2e_test.go` with OpenTelemetry support
   - **Command**: `make e2e-tests`
   - **This is the correct command to use!**

2. **`tests/e2e/e2e_test.go`**
   - **Status**: ✅ UP TO DATE
   - **Location**: `tests/e2e/e2e_test.go`
   - **What it does**: Comprehensive e2e tests with OpenTelemetry observability stack
   - Includes:
     - OpenTelemetry Collector deployment
     - Prometheus scraping from OTel Collector
     - Loki log collection
     - Tempo trace export
     - Grafana dashboard verification

3. **`scripts/setup-observability-stack.sh`**
   - **Status**: ✅ UP TO DATE
   - **Location**: `scripts/setup-observability-stack.sh`
   - **What it does**: Deploys complete observability stack (OTel Collector, Prometheus, Loki, Tempo, Grafana)

### ❌ OUTDATED

1. **`scripts/e2e-demo.sh`**
   - **Status**: ❌ OUTDATED
   - **Issues**:
     - Uses old Prometheus-only setup (no OpenTelemetry)
     - References `/metrics` endpoint (doesn't exist with OTel)
     - Doesn't deploy OTel Collector, Loki, Tempo
     - Uses old Grafana dashboard location (`grafana/dashboard.json`)
   - **Recommendation**: Use `scripts/e2e-demo-otel.sh` instead

2. **`scripts/run-e2e-demo.sh`**
   - **Status**: ❌ OUTDATED (mostly)
   - **Issues**:
     - References old Grafana dashboard (`grafana/dashboard.json`)
     - Uses old Prometheus-only monitoring setup
     - Doesn't include OpenTelemetry observability stack
   - **Recommendation**: Use `scripts/e2e-demo-otel.sh` instead

## Recommended Commands

### For Automated E2E Testing (Recommended)

```bash
# Run comprehensive e2e tests (includes OpenTelemetry stack)
make e2e-tests
```

This will:
- ✅ Check prerequisites (kind, kubectl, helm, curl)
- ✅ Build application
- ✅ Create kind cluster
- ✅ Deploy OpenTelemetry observability stack
- ✅ Deploy application with OTel configuration
- ✅ Run all e2e tests
- ✅ Verify metrics, logs, and traces

### For Interactive Demo with Observability Stack

```bash
# Run updated demo script with OpenTelemetry
./scripts/e2e-demo-otel.sh
```

This will:
- ✅ Build and test application
- ✅ Create kind cluster
- ✅ Deploy complete observability stack (OTel Collector, Prometheus, Loki, Tempo, Grafana)
- ✅ Deploy application with OpenTelemetry enabled
- ✅ Generate traffic to create telemetry data
- ✅ Provide instructions to access Grafana dashboards

### For Manual Step-by-Step

```bash
# Step 1: Deploy observability stack
./scripts/setup-observability-stack.sh

# Step 2: Deploy application with local testing values
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  -f ./chart/dm-nkp-gitops-custom-app/values-local-testing.yaml \
  --set image.tag=demo \
  --set image.pullPolicy=Never

# Step 3: Generate traffic
kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080 &
for i in {1..100}; do curl -s http://localhost:8080/ >/dev/null; sleep 0.1; done

# Step 4: Access Grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80
# Open: http://localhost:3000 (admin/admin)
```

## CI/CD Status

### CI Workflow (`.github/workflows/ci.yml`)

- **Status**: ✅ UP TO DATE (assumed, based on Makefile target)
- **What it uses**: `make e2e-tests` which runs `tests/e2e/e2e_test.go`
- **Recommendation**: Verify CI uses `make e2e-tests` (not the bash scripts)

### CD Workflow (`.github/workflows/cd.yml`)

- **Status**: ✅ UP TO DATE (assumed)
- **What it uses**: Similar e2e tests after pushing artifacts
- **Recommendation**: Verify CD workflow is using correct e2e tests

## New Script: `e2e-demo-otel.sh`

I've created a new updated script that replaces `e2e-demo.sh`:

**Location**: `scripts/e2e-demo-otel.sh`

**Features**:
- ✅ OpenTelemetry observability stack deployment
- ✅ OTel Collector, Prometheus, Loki, Tempo, Grafana
- ✅ Application deployment with OTel configuration
- ✅ Traffic generation for telemetry data
- ✅ Instructions for accessing Grafana dashboards

**Usage**:
```bash
./scripts/e2e-demo-otel.sh
```

## Migration Guide

### Old Way (Outdated)

```bash
# ❌ DON'T USE - Outdated
./scripts/e2e-demo.sh
```

### New Way (Recommended)

```bash
# ✅ USE - Automated tests
make e2e-tests

# ✅ USE - Interactive demo
./scripts/e2e-demo-otel.sh
```

## Summary

**For Testing**:
```bash
make e2e-tests  # ✅ Recommended
```

**For Demo**:
```bash
./scripts/e2e-demo-otel.sh  # ✅ Updated script
```

**For Manual Setup**:
```bash
./scripts/setup-observability-stack.sh  # ✅ Up to date
helm install app ./chart/dm-nkp-gitops-custom-app -f values-local-testing.yaml
```

## Action Items

1. ✅ Use `make e2e-tests` for automated testing
2. ✅ Use `scripts/e2e-demo-otel.sh` for interactive demo (new script created)
3. ⚠️ **Consider deprecating**: `scripts/e2e-demo.sh` and `scripts/run-e2e-demo.sh`
4. ⚠️ **Update documentation** to reference new script names
5. ⚠️ **Verify CI/CD workflows** use `make e2e-tests` (not bash scripts)
