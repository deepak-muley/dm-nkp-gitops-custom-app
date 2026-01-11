# Documentation Organization

⚠️ **DEPRECATED**: This document has been replaced by **[docs/README.md](README.md)** - The new comprehensive documentation index.

Please use **[docs/README.md](README.md)** instead for:
- Organized learning paths
- Topic-based categories  
- Recommended reading order
- Current documentation structure

---

## Historical Information (For Reference Only)

## Documentation Files Moved to `docs/`

All documentation files have been moved from root to `docs/` folder for better organization.

### Files Moved

The following documentation files were moved from root to `docs/`:

| Old Location (Root) | New Location (docs/) |
|---------------------|---------------------|
| `E2E_UPDATE_SUMMARY.md` | `docs/E2E_UPDATE_SUMMARY.md` |
| `E2E_DEMO.md` | `docs/E2E_DEMO.md` |
| `MIGRATION_SUMMARY.md` | `docs/MIGRATION_SUMMARY.md` |
| `OPENTELEMETRY_QUICK_START.md` | `docs/OPENTELEMETRY_QUICK_START.md` |
| `QUICK_START.md` | `docs/QUICK_START.md` |

### Files That Stay at Root

Standard project files remain at root (as per standard project structure):

- `README.md` - Main project readme
- `CHANGELOG.md` - Project changelog
- `CODE_OF_CONDUCT.md` - Code of conduct
- `CONTRIBUTING.md` - Contributing guidelines
- `SECURITY.md` - Security policy
- `LICENSE` - License file

These are standard project files that should remain at root for GitHub/GitLab visibility.

### All References Updated

All internal references to moved documentation files have been updated to point to their new locations in `docs/`.

---

## Final Command for Local E2E Testing

**The final command to run end-to-end tests locally:**

```bash
make e2e-tests
```

### What It Does

- ✅ Checks prerequisites (kind, curl)
- ✅ Runs comprehensive e2e tests from `tests/e2e/e2e_test.go`
- ✅ Creates kind cluster automatically
- ✅ Deploys OpenTelemetry observability stack (OTel Collector, Prometheus, Loki, Tempo, Grafana)
- ✅ Deploys application with OpenTelemetry configuration
- ✅ Tests complete telemetry pipeline (metrics, logs, traces)
- ✅ Timeout: 30 minutes

### Alternative: Interactive Demo

For an interactive demo with step-by-step instructions:

```bash
./scripts/e2e-demo-otel.sh
```

**Difference**:
- `make e2e-tests`: Automated testing (recommended for CI/testing)
- `./scripts/e2e-demo-otel.sh`: Interactive demo with detailed output (recommended for learning/demo)

---

## Documentation Structure

```
docs/
├── E2E_*.md                      # End-to-end testing guides
├── OPENTELEMETRY_*.md            # OpenTelemetry guides
├── MIGRATION_*.md                # Migration guides
├── QUICK_START.md                # Quick start guide
├── PLATFORM_*.md                 # Platform dependencies guides
├── LOGGING_OPERATOR_*.md         # Logging operator explanations
├── OBSERVABILITY_*.md            # Observability guides
├── RUNNING_E2E_TESTS*.md         # E2E testing guides
├── HELM_CHART_*.md               # Helm chart references
└── ... (other documentation)
```

---

## Quick Reference

### Run E2E Tests Locally

```bash
# Recommended command
make e2e-tests

# Alternative: Interactive demo
./scripts/e2e-demo-otel.sh
```

### Access Grafana After Tests

```bash
kubectl port-forward -n observability svc/prometheus-grafana 3000:80
open http://localhost:3000
# Login: admin/admin
```

### Cleanup

```bash
kind delete cluster --name dm-nkp-test-cluster
```

---

## Related Documentation

- [docs/E2E_QUICK_REFERENCE.md](E2E_QUICK_REFERENCE.md) - Quick reference for e2e testing
- [docs/RUNNING_E2E_TESTS_LOCALLY.md](RUNNING_E2E_TESTS_LOCALLY.md) - Complete guide for local e2e testing
- [docs/RUNNING_E2E_TESTS.md](RUNNING_E2E_TESTS.md) - Detailed e2e testing guide
- [docs/E2E_DEMO.md](E2E_DEMO.md) - Step-by-step demo guide
- [docs/OPENTELEMETRY_QUICK_START.md](OPENTELEMETRY_QUICK_START.md) - OpenTelemetry quick start
