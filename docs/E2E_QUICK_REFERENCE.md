# End-to-End Testing - Quick Reference

## Final Command to Run E2E Tests Locally

### ✅ Recommended Command

```bash
make e2e-tests
```

**This is the final command to run end-to-end tests locally.**

### What It Does

- ✅ Checks prerequisites (kind, curl)
- ✅ Runs Go e2e tests from `tests/e2e/e2e_test.go`
- ✅ Creates kind cluster automatically
- ✅ Deploys OpenTelemetry observability stack
- ✅ Deploys application with OTel configuration
- ✅ Tests complete telemetry pipeline (metrics, logs, traces)
- ✅ Timeout: 30 minutes

### Prerequisites

```bash
# Required tools
kind      # Kubernetes in Docker
kubectl   # Kubernetes CLI
helm      # Helm 3.x
docker    # Docker running
curl      # For HTTP requests
go        # Go 1.25+
```

### Alternative: Interactive Demo

If you want an **interactive demo** with step-by-step instructions:

```bash
./scripts/e2e-demo-otel.sh
```

**Difference**:
- `make e2e-tests`: Automated testing (recommended)
- `./scripts/e2e-demo-otel.sh`: Interactive demo with detailed output and instructions

### Access Grafana After Tests

```bash
# Port forward to Grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80

# Open browser
open http://localhost:3000
# Login: admin/admin

# View dashboards:
# - Metrics: Browse → dm-nkp-gitops-custom-app - Metrics
# - Logs: Browse → dm-nkp-gitops-custom-app - Logs
# - Traces: Browse → dm-nkp-gitops-custom-app - Traces
```

### Cleanup

```bash
# Delete kind cluster when done
kind delete cluster --name dm-nkp-test-cluster
```

---

## Summary

**Final Command**:
```bash
make e2e-tests
```

**Alternative**:
```bash
./scripts/e2e-demo-otel.sh
```

**Documentation**:
- [docs/RUNNING_E2E_TESTS_LOCALLY.md](RUNNING_E2E_TESTS_LOCALLY.md) - Complete guide
- [docs/RUNNING_E2E_TESTS.md](RUNNING_E2E_TESTS.md) - Detailed e2e testing guide
- [docs/E2E_DEMO.md](E2E_DEMO.md) - Step-by-step demo guide
