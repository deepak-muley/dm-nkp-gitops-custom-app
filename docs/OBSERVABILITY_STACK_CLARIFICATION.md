# Observability Stack Chart - Clarification

## Important Clarification

### ❓ Question: Who Installs the Observability Stack Configs?

**Answer**: It depends on the environment!

## Two Different Scenarios

### Scenario 1: Local Testing (Development/Testing)

**Who installs**: **You (developer)** install the `observability-stack` chart

**How it works**:
```bash
# Developer installs the observability-stack chart for local testing
helm install observability-stack ./chart/observability-stack \
  --namespace observability \
  --create-namespace
```

**What gets created**:
- ✅ `otel-collector-config.yaml` ConfigMap (from `chart/observability-stack/templates/otel-collector-config.yaml`)
- ✅ OTel Collector Deployment
- ✅ Prometheus (via kube-prometheus-stack)
- ✅ Loki
- ✅ Tempo
- ✅ Grafana

**Purpose**: Quick local setup for development/testing

**Chart Location**: `chart/observability-stack/`

---

### Scenario 2: Production (Platform-Managed)

**Who installs**: **Platform Engineering Team** deploys OTel Collector separately

**How it works**:
```bash
# Platform team deploys OTel Collector (NOT using our chart)
helm install otel-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  --values platform-otel-collector-values.yaml  # Platform's own config
```

**What gets created**:
- ✅ OTel Collector Deployment (by platform team, using their own config)
- ✅ Prometheus (pre-deployed by platform team)
- ✅ Loki (pre-deployed by platform team)
- ✅ Tempo (pre-deployed by platform team)
- ✅ Grafana (pre-deployed by platform team)
- ❌ **NOT created**: Our `otel-collector-config.yaml` ConfigMap (platform uses their own config)

**Purpose**: Production-ready, platform-managed observability infrastructure

**Our chart is NOT used**: Platform team uses official upstream charts or their own custom charts

---

## Key Points

### 1. Observability Stack Chart is Optional and Local-Only

**Location**: `chart/observability-stack/`

**Purpose**: 
- ✅ For **local development/testing** only
- ❌ **NOT** for production
- ❌ **NOT** used by platform engineering team

**When to use**:
- Local kind/minikube clusters
- E2E testing
- Learning/development

**When NOT to use**:
- Production Kubernetes clusters (platform team manages this)
- CI/CD pipelines (unless testing locally)

### 2. ConfigMaps in Observability Stack Chart

**Template**: `chart/observability-stack/templates/otel-collector-config.yaml`

**Created only if**:
```bash
# Someone explicitly installs the observability-stack chart
helm install observability-stack ./chart/observability-stack
```

**NOT created if**:
- ❌ Platform team deploys OTel Collector separately (they use their own config)
- ❌ You only deploy the application chart (app chart doesn't install observability-stack)

### 3. Application Chart Does NOT Install Observability Stack

**Application Chart**: `chart/dm-nkp-gitops-custom-app/`

**What it does**:
- ✅ Deploys application (Deployment, Service)
- ✅ Deploys app-specific CRs:
  - ServiceMonitor (references pre-deployed OTel Collector)
  - Grafana Dashboard ConfigMaps
- ❌ **Does NOT** deploy OTel Collector
- ❌ **Does NOT** deploy Prometheus/Loki/Tempo/Grafana
- ❌ **Does NOT** install observability-stack chart

**How it references platform services**:
```yaml
# Application values.yaml
opentelemetry:
  collector:
    endpoint: "otel-collector.observability.svc.cluster.local:4317"  # References platform service

monitoring:
  serviceMonitor:
    otelCollector:
      namespace: "observability"  # References platform namespace
      selectorLabels:
        component: otel-collector  # Matches platform's OTel Collector labels
```

### 4. Platform Engineering Team Responsibilities

**Platform team deploys** (using their own methods):
- OTel Collector (official chart or custom)
- Prometheus Operator + Prometheus
- Loki
- Tempo
- Grafana

**Platform team configures**:
- OTel Collector configuration (their own values/config)
- Service names, namespaces, labels
- Resource limits, storage, retention policies
- Security, authentication, TLS

**Platform team documents**:
- Service endpoints (for applications to reference)
- Namespaces
- Selector labels (for ServiceMonitor matching)
- Configuration values applications should use

### 5. Application Team Responsibilities

**Application team deploys** (using application chart):
- Application itself (Deployment, Service)
- App-specific Custom Resources:
  - ServiceMonitor (selects platform's OTel Collector)
  - Grafana Dashboard ConfigMaps (auto-discovered by platform's Grafana)

**Application team configures**:
- OTel endpoint (references platform service)
- ServiceMonitor selector labels (match platform's OTel Collector)
- Dashboard namespace (where platform's Grafana can discover them)

**Application team does NOT**:
- ❌ Deploy OTel Collector
- ❌ Deploy Prometheus/Loki/Tempo/Grafana
- ❌ Configure platform infrastructure

---

## Visual Representation

### Local Testing Setup

```
Developer Machine
│
├─> helm install observability-stack ./chart/observability-stack
│   └─> Creates:
│       ├─> otel-collector-config.yaml (ConfigMap)
│       ├─> OTel Collector (Deployment)
│       ├─> Prometheus
│       ├─> Loki
│       ├─> Tempo
│       └─> Grafana
│
└─> helm install app ./chart/dm-nkp-gitops-custom-app
    └─> Creates:
        ├─> Application (Deployment, Service)
        ├─> ServiceMonitor (references OTel Collector above)
        └─> Dashboard ConfigMaps (for Grafana above)
```

### Production Setup

```
Platform Engineering
│
└─> Deploys observability infrastructure (using their own charts/configs)
    ├─> OTel Collector (their config, not our chart)
    ├─> Prometheus
    ├─> Loki
    ├─> Tempo
    └─> Grafana

Application Team
│
└─> helm install app ./chart/dm-nkp-gitops-custom-app \
      --set opentelemetry.collector.endpoint=otel-collector.observability.svc.cluster.local:4317
    └─> Creates:
        ├─> Application (Deployment, Service)
        ├─> ServiceMonitor (references platform's OTel Collector)
        └─> Dashboard ConfigMaps (discovered by platform's Grafana)
```

**Key Difference**: 
- ❌ Application chart does NOT deploy OTel Collector in production
- ✅ Application chart only references pre-deployed platform services

---

## Summary

### Observability Stack Chart (`chart/observability-stack/`)

**Purpose**: Local testing only

**Installed by**: Developer (for local testing)

**Contains**: Templates like `otel-collector-config.yaml` that create ConfigMaps/Deployments

**When used**:
- ✅ Local kind/minikube clusters
- ✅ E2E testing
- ✅ Development/learning

**When NOT used**:
- ❌ Production (platform team deploys separately)
- ❌ CI/CD (unless testing locally)

### Application Chart (`chart/dm-nkp-gitops-custom-app/`)

**Purpose**: Deploy application + app-specific CRs

**Installed by**: Application team

**Does NOT contain**: OTel Collector configs (those are in observability-stack chart)

**Does create**:
- Application resources
- ServiceMonitor (references platform's OTel Collector)
- Dashboard ConfigMaps (discovered by platform's Grafana)

**References**: Pre-deployed platform services (via configurable values)

### Platform Team

**Deploys**: OTel Collector, Prometheus, Loki, Tempo, Grafana (using their own charts/configs)

**Does NOT use**: Our `observability-stack` chart (they use official charts or their own)

**Configures**: OTel Collector configuration themselves (not our ConfigMap template)

---

## FAQ

### Q: Will `otel-collector-config.yaml` be auto-installed in production?

**A**: ❌ **NO**. It's only installed if someone explicitly installs the `observability-stack` chart. In production, platform team deploys OTel Collector separately and configures it themselves.

### Q: Are these default configs that platform team should use?

**A**: ❌ **NO**. These are example configs for local testing. Platform team uses their own production-ready configurations based on their requirements (storage, retention, security, etc.).

### Q: Does the application chart automatically install the observability-stack chart?

**A**: ❌ **NO**. The application chart does NOT depend on or install the observability-stack chart. It only references pre-deployed platform services via configurable values.

### Q: How does the application chart know where to find OTel Collector?

**A**: Via configurable Helm values:
```yaml
opentelemetry:
  collector:
    endpoint: "otel-collector.observability.svc.cluster.local:4317"  # Platform service
```

Platform team documents the service name/namespace, and application team configures it.

### Q: What if I want to use the observability-stack chart in production?

**A**: ❌ **Don't**. The chart is explicitly marked "LOCAL TESTING ONLY" for a reason. In production:
- Platform team manages observability infrastructure
- They need control over configuration, resources, security
- They use official upstream charts or their own custom charts
- Separation of concerns (platform vs application)

---

## Correct Usage

### Local Testing

```bash
# 1. Deploy observability stack (local testing only)
helm install observability-stack ./chart/observability-stack \
  --namespace observability \
  --create-namespace

# 2. Deploy application
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  -f values-local-testing.yaml
```

### Production

```bash
# 1. Platform team deploys infrastructure (separate process, not our chart)
# They use: open-telemetry/opentelemetry-collector chart with their config

# 2. Application team deploys application (references platform services)
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  -f values-production.yaml \
  --set opentelemetry.collector.endpoint=otel-collector.observability.svc.cluster.local:4317
```

---

## Conclusion

- ✅ **Observability stack chart** = For local testing only (you install it)
- ✅ **Application chart** = Deploys app + app-specific CRs (references platform services)
- ✅ **Platform team** = Deploys infrastructure separately (their own charts/configs)
- ❌ **No auto-installation** of observability-stack chart in production
- ❌ **No default configs** for production (platform team configures)

The `otel-collector-config.yaml` template is **only** used when you explicitly install the `observability-stack` chart for local testing. It's **not** used in production where platform team manages OTel Collector separately.
