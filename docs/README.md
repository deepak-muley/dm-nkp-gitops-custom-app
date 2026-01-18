# Documentation Index

> **📚 Complete documentation for dm-nkp-gitops-custom-app**

---

## 🚀 Quick Start

| Document | Description | Time |
|----------|-------------|------|
| [Quick Start](QUICK_START.md) | Build and run locally | 5 min |
| [OpenTelemetry Quick Start](OPENTELEMETRY_QUICK_START.md) | Deploy observability stack | 15 min |
| [E2E Demo](E2E_DEMO.md) | Full end-to-end demo | 20 min |

**Recommended first read**: Start with the [Core Application & Telemetry](../README.md#core-application--telemetry) section in the main README.

---

## 📖 Documentation by Topic

### 🔭 Observability & Monitoring

| Document | Description |
|----------|-------------|
| [Grafana Beginner Guide](GRAFANA_BEGINNER_GUIDE.md) ⭐ | Understanding dashboards, datasources, and auto-discovery |
| [Grafana Dashboard Queries](grafana-dashboard-queries.md) | All PromQL, LogQL, TraceQL queries with architecture diagrams |
| [OpenTelemetry Workflow](opentelemetry-workflow.md) | Complete telemetry data flow |
| [OpenTelemetry Standard Practices](opentelemetry-standard-practices.md) | Best practices for OTel |
| [Troubleshooting Logs & Traces](troubleshooting-logs-traces.md) | Debug missing data in Grafana |

### 📊 Log Collection

| Document | Description |
|----------|-------------|
| [Duplicate Log Collection](DUPLICATE_LOG_COLLECTION.md) ⚠️ | Avoid duplicate logs (OTel vs Logging Operator) |
| [Logging Operator Default Behavior](LOGGING_OPERATOR_DEFAULT_BEHAVIOR.md) | How FluentBit/Fluentd collect logs |
| [OTel Collector for Logs](why-otel-collector-not-enough-for-logs.md) | Why you might need both |
| [OTLP Logs Standard Approach](otlp-logs-standard-approach.md) | Loki 3.0+ OTLP ingestion |

### 🚀 Deployment & Operations

| Document | Description |
|----------|-------------|
| [Deployment Guide](DEPLOYMENT_GUIDE.md) | Production deployment |
| [Helm Chart Installation](HELM_CHART_INSTALLATION_REFERENCE.md) | Helm chart reference |
| [Platform Dependencies](PLATFORM_DEPENDENCIES.md) | What platform provides |
| [NKP Deployment](NKP_DEPLOYMENT.md) | Nutanix NKP specifics |

### 🧪 Testing

| Document | Description |
|----------|-------------|
| [E2E Quick Reference](E2E_QUICK_REFERENCE.md) | Quick E2E test commands |
| [Running E2E Tests Locally](RUNNING_E2E_TESTS_LOCALLY.md) | Detailed E2E guide |
| [Testing Guide](testing.md) | All testing approaches |

### 🔄 CI/CD

| Document | Description |
|----------|-------------|
| [CI/CD Pipeline](cicd-pipeline.md) | Complete pipeline overview |
| [GitHub Actions Reference](github-actions-reference.md) | All workflows documented |
| [GitHub Actions Setup](github-actions-setup.md) | Setup guide |

### 🔒 Security

| Document | Description |
|----------|-------------|
| [Security Guide](security.md) | Security practices |
| [Image Signing](image-signing.md) | Cosign setup and signing |
| [OpenSSF Scorecard](openssf-scorecard.md) | Security scorecard |
| [Production Ready Checklist](production-ready-checklist.md) | Pre-production checklist |

### 🛠️ Development

| Document | Description |
|----------|-------------|
| [Development Guide](development.md) | Local development setup |
| [Metrics Documentation](metrics.md) | Available metrics |
| [Buildpacks Guide](buildpacks.md) | Container builds |
| [Pre-commit Setup](pre-commit-setup.md) | Code quality hooks |

### 🏗️ Architecture

| Document | Description |
|----------|-------------|
| [Architecture Decision Records](adr/) | Technical decisions |
| [Model Repository Template](model-repository-template.md) | Replicate this setup |
| [Replication Checklist](REPLICATION_CHECKLIST.md) | Step-by-step replication |
| [Manifests vs Helm](manifests-vs-helm.md) | Deployment approaches |

### 📦 Platform Integration

| Document | Description |
|----------|-------------|
| [Gateway API Path-Based Routing](gateway-api-path-based-routing.md) | HTTPRoute configuration |
| [Let's Encrypt Gateway API Setup](lets-encrypt-gateway-api-setup.md) | TLS with cert-manager |
| [OTel Collector Multiple Receivers](otel-collector-multiple-receivers.md) | Advanced collector config |

---

## 🎯 Quick Reference by Task

**"I want to..."**

| Task | Read This |
|------|-----------|
| Get started quickly | [Quick Start](QUICK_START.md) → [E2E Demo](E2E_DEMO.md) |
| Understand monitoring | [Grafana Beginner Guide](GRAFANA_BEGINNER_GUIDE.md) |
| See all dashboard queries | [Grafana Dashboard Queries](grafana-dashboard-queries.md) |
| Deploy to production | [Deployment Guide](DEPLOYMENT_GUIDE.md) |
| Run E2E tests | `./scripts/e2e-demo-otel.sh` or `make e2e-tests` |
| Troubleshoot missing data | [Troubleshooting Logs & Traces](troubleshooting-logs-traces.md) |
| Avoid duplicate logs | [Duplicate Log Collection](DUPLICATE_LOG_COLLECTION.md) |
| Set up CI/CD | [GitHub Actions Setup](github-actions-setup.md) |
| Replicate this setup | [Model Repository Template](model-repository-template.md) |

---

## 📊 Architecture Diagrams

### Observability Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        dm-nkp-gitops-custom-app                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │  OTel Metrics   │  │   OTel Logs     │  │  OTel Traces    │             │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘             │
│           └────────────────────┼────────────────────┘                       │
│                                │ OTLP (gRPC :4317)                          │
└────────────────────────────────┼────────────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                      OpenTelemetry Collector                               │
│   Receivers: otlp (gRPC :4317, HTTP :4318)                                 │
│   Processors: batch, resource                                              │
│   Exporters: prometheus, otlphttp/loki, otlp/tempo                         │
└─────────────┬──────────────────────┬──────────────────────┬────────────────┘
              │                      │                      │
              ▼                      ▼                      ▼
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│     Prometheus      │  │    Loki 3.0+        │  │       Tempo         │
│     (port 9090)     │  │  (gateway :80)      │  │   (port 3200/4317)  │
└──────────┬──────────┘  └──────────┬──────────┘  └──────────┬──────────┘
           └────────────────────────┼────────────────────────┘
                                    ▼
                    ┌───────────────────────────────┐
                    │           Grafana             │
                    │         (port 3000)           │
                    │   Dashboards: Metrics, Logs,  │
                    │               Traces          │
                    └───────────────────────────────┘
```

### Log Collection (Dual Path)

```
┌───────────────────────────────────────────────────────────────────────────┐
│                        Application                                         │
│   telemetry.LogInfo(ctx, "message")                                       │
│   → OTLP (OTel SDK)                    → stdout/stderr (for FluentBit)    │
└───────────────┬────────────────────────────────────┬──────────────────────┘
                │                                    │
                ▼                                    ▼
┌───────────────────────────┐        ┌───────────────────────────────────────┐
│   OTel Collector          │        │   Logging Operator (FluentBit)        │
│   Labels:                 │        │   Labels:                             │
│   - service_name          │        │   - namespace, pod, container         │
│   - severity_text         │        │   - app_kubernetes_io_name            │
└─────────────┬─────────────┘        └──────────────────┬────────────────────┘
              │ /otlp/v1/logs                           │ /loki/api/v1/push
              └────────────────────┬───────────────────┘
                                   ▼
                   ┌───────────────────────────────┐
                   │         Loki 3.0+             │
                   │                               │
                   │  OTLP: {service_name="..."}   │
                   │  FluentBit: {namespace="..."}  │
                   └───────────────────────────────┘
```

---

## ⚠️ Deprecated Documents (Don't Read)

These documents are outdated or have been consolidated into the documents above:

### Historical/Summary Docs (Skip)

- `COMPLETE_SETUP_SUMMARY.md`, `COMPLETE_WORKFLOW.md`, `SETUP_COMPLETE.md`
- `MIGRATION_SUMMARY.md`, `DOCUMENTATION_ORGANIZATION.md`, `DOCUMENTATION_CONSOLIDATION.md`
- `E2E_TESTING_UPDATE.md`, `E2E_UPDATE_SUMMARY.md`
- `OBSERVABILITY_COMPLETE.md`, `OBSERVABILITY_STACK_COMPLETE.md`, `OBSERVABILITY_STACK_CLARIFICATION.md`
- `LOGGING_OPERATOR_AND_PLATFORM_DEPENDENCIES.md`, `LOGGING_OPERATOR_AND_PLATFORM_DEPENDENCIES_SUMMARY.md`
- `LOGGING_OPERATOR_EXPLANATION.md`, `logging-operator-fixes.md`

### Consolidated Docs

- `README_OBSERVABILITY.md` → Consolidated into [OpenTelemetry Quick Start](OPENTELEMETRY_QUICK_START.md)
- `GRAFANA_DASHBOARDS_SETUP.md`, `GRAFANA_DASHBOARDS_COMPLETE.md` → Consolidated into [Grafana Beginner Guide](GRAFANA_BEGINNER_GUIDE.md)
- `grafana-dashboard-fixes.md` → Consolidated into [Grafana Dashboard Queries](grafana-dashboard-queries.md)
- `RUNNING_E2E_TESTS.md` → Duplicate of [Running E2E Tests Locally](RUNNING_E2E_TESTS_LOCALLY.md)

### Internal/Meta Docs (Skip)

- `markdownlint-fixes.md`, `VIDEO_DEMO_SCRIPT.md`, `VIDEO_RECORDING_CHECKLIST.md`
- `WHY_SEPARATE_OBSERVABILITY_STACK.md`, `why-no-agent-needed.md`

---

## 🎓 Recommended Learning Path

**For beginners (total ~60 min):**

1. **[Quick Start](QUICK_START.md)** (5 min) - Get running locally
2. **[Core App & Telemetry](../README.md#core-application--telemetry)** (10 min) - Understand the app
3. **[Grafana Beginner Guide](GRAFANA_BEGINNER_GUIDE.md)** (15 min) - Learn dashboards
4. **[OpenTelemetry Quick Start](OPENTELEMETRY_QUICK_START.md)** (10 min) - Deploy stack
5. **[E2E Demo](E2E_DEMO.md)** (15 min) - See it all working
6. **[Grafana Dashboard Queries](grafana-dashboard-queries.md)** (5 min) - Reference queries

---

## 📝 Key Scripts

| Script | Description |
|--------|-------------|
| `./scripts/e2e-demo-otel.sh` | Full E2E demo with OpenTelemetry stack |
| `./scripts/debug-logs-traces.sh` | Debug missing logs/traces |
| `./scripts/generate-load.sh` | Generate test traffic |
| `make e2e-tests` | Run automated E2E tests |

---

## 💡 Tips

1. **Start with E2E Demo** - `./scripts/e2e-demo-otel.sh` sets up everything
2. **Use architecture diagrams** - Found in [Grafana Dashboard Queries](grafana-dashboard-queries.md)
3. **Check troubleshooting** - [Troubleshooting Logs & Traces](troubleshooting-logs-traces.md) if data missing
4. **Understand dual log paths** - [Duplicate Log Collection](DUPLICATE_LOG_COLLECTION.md) explains FluentBit vs OTLP

---

**Questions?** Check [Troubleshooting Guide](TROUBLESHOOTING.md) or open an issue.
