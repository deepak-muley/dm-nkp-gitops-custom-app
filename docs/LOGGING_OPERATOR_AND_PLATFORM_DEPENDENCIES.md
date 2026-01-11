# Logging Operator vs OpenTelemetry Collector - When to Use Each

## Why Logging Operator is NOT Used in This Setup

### Current Architecture

**Our Setup:**
```
Application → OTLP (gRPC/HTTP) → OpenTelemetry Collector → Loki
                              ↓
                         (Direct export)
```

**What We're Using:**
- **OpenTelemetry Collector** - Unified collector for metrics, logs, and traces
- **OTLP Protocol** - OpenTelemetry standard protocol
- **Direct Loki Exporter** - OTel Collector forwards logs directly to Loki via Loki exporter

### Why Logging Operator is NOT Needed

1. **Unified Collection Point**: OpenTelemetry Collector already handles log collection
   - Applications export logs via OTLP (OpenTelemetry standard)
   - OTel Collector receives logs and forwards to Loki
   - No need for additional log collection infrastructure

2. **Simpler Architecture**: One collector for all telemetry types
   - Metrics → OTel Collector → Prometheus
   - Logs → OTel Collector → Loki
   - Traces → OTel Collector → Tempo
   - **Single point of collection, routing, and processing**

3. **Application Instrumentation**: Applications are already instrumented with OpenTelemetry
   - Structured logging via OTLP
   - Automatic log export
   - No need for sidecar containers or DaemonSets

4. **OTLP is Standard**: Industry-standard protocol
   - Works across languages and frameworks
   - Vendor-agnostic
   - Future-proof

### Current Log Collection Flow

```
Application (Go)
├── Logs to stdout/stderr (structured)
└── OTLP Export → OTel Collector (logs pipeline)
                   ↓
              Loki Exporter
                   ↓
               Loki (/api/v1/push)
```

**How It Works:**
- Application logs to stdout/stderr (standard Go logging)
- OTel Collector configured to receive logs via OTLP (HTTP/gRPC)
- OTel Collector processes and forwards to Loki via Loki exporter
- Loki stores and indexes logs
- Grafana queries Loki for visualization

**No Logging Operator Required!**

## When WOULD You Use Logging Operator?

Logging Operator would be useful in these scenarios:

### Scenario 1: Mixed Application Stack (OTel + Non-OTel Apps)

**Use Case**: You have applications that:
- Don't have OpenTelemetry instrumentation
- Use different logging formats
- Need automatic log collection without code changes
- Include third-party applications you can't modify

**Architecture with Logging Operator:**
```
Applications (Mixed Stack)
├── OTel Apps → OTel Collector → Loki (via OTLP)
└── Non-OTel Apps → Logging Operator → Fluent Bit/D → Loki
                    ↓
              (Automatic collection from pods)
```

**Benefits:**
- Automatic log collection from all pods (including system pods)
- Works with any application (no code changes needed)
- Uses Fluent Bit/D for log processing
- Can collect logs from node-level (system logs)

**When to Use:**
- ✅ Legacy applications without OTel instrumentation
- ✅ Third-party applications you can't modify
- ✅ Need to collect system/Kubernetes logs
- ✅ Want automatic log collection without application changes
- ✅ Mixed stack (OTel + non-OTel applications)

### Scenario 2: Advanced Log Routing and Filtering

**Use Case**: You need:
- Advanced log routing based on labels/namespaces
- Complex log transformations at infrastructure level
- Multi-destination routing (different log stores)
- Centralized log processing policies

**Logging Operator Features:**
- **Output CRs**: Route logs to different destinations
- **Flow CRs**: Route logs based on filters/matches
- **ClusterOutput CRs**: Shared outputs across namespaces
- **ClusterFlow CRs**: Global log routing policies

**Example:**
```yaml
# Route logs based on namespace
apiVersion: logging.banzaicloud.io/v1beta1
kind: Flow
metadata:
  name: production-logs
  namespace: production
spec:
  match:
    - select:
        namespaces:
          - production
  localOutputRefs:
    - production-loki
```

**When to Use:**
- ✅ Need namespace-based log routing
- ✅ Complex log filtering/transformation at infrastructure level
- ✅ Multiple log destinations (dev Loki, prod Loki, S3 archive)
- ✅ Centralized log processing policies

### Scenario 3: Node-Level Log Collection

**Use Case**: You need to collect:
- Kubernetes system logs (kubelet, kube-proxy, etc.)
- Node-level logs
- Container runtime logs
- Logs from applications running as DaemonSets

**Logging Operator Approach:**
- Deploys Fluent Bit as DaemonSet on each node
- Automatically collects logs from `/var/log/containers`
- Processes and routes to Loki
- No application changes required

**When to Use:**
- ✅ Need to collect system/Kubernetes logs
- ✅ Node-level log collection required
- ✅ Container runtime logs needed
- ✅ Applications running as DaemonSets

### Scenario 4: Compliance and Audit Logging

**Use Case**: You need:
- Centralized audit logging
- Compliance requirements (retention, encryption)
- Log integrity verification
- Different retention policies per application/namespace

**Logging Operator Benefits:**
- Centralized log collection policies
- Configurable retention per Flow/Output
- Audit trail of log routing
- Compliance-ready configurations

**When to Use:**
- ✅ Compliance requirements (GDPR, HIPAA, SOC2)
- ✅ Different retention policies per namespace
- ✅ Audit logging requirements
- ✅ Log integrity verification needed

## Comparison: Logging Operator vs OpenTelemetry Collector

| Feature | Logging Operator | OpenTelemetry Collector |
|---------|-----------------|------------------------|
| **Primary Use** | Log collection only | Metrics, Logs, Traces (unified) |
| **Collection Method** | Automatic (Fluent Bit/D DaemonSet) | Application export (OTLP) |
| **Protocol** | Fluentd/Fluent Bit protocols | OTLP (OpenTelemetry standard) |
| **Code Changes** | ❌ Not required | ✅ Application instrumentation |
| **Works With** | Any application (legacy OK) | OTel-instrumented apps |
| **Unified Collection** | ❌ Logs only | ✅ Metrics, Logs, Traces |
| **Industry Standard** | Fluentd ecosystem | OpenTelemetry (CNCF) |
| **Routing/Filtering** | ✅ Advanced (Flow CRs) | ✅ Good (OTel processors) |
| **Node-Level Logs** | ✅ Yes (DaemonSet) | ❌ Requires sidecar |
| **System Logs** | ✅ Yes | ❌ Limited |
| **Setup Complexity** | Medium (CRDs + Fluent Bit) | Low (single collector) |
| **Best For** | Mixed stack, legacy apps | Modern, OTel-instrumented apps |

## Recommendation for This Project

### Current Setup is Correct (OTel Collector Only)

**Why:**
- ✅ Application is OpenTelemetry-instrumented
- ✅ Unified collection for all telemetry types
- ✅ Simpler architecture (one collector)
- ✅ Industry-standard OTLP protocol
- ✅ No need for additional infrastructure

**When to Add Logging Operator:**

Only if you need:
1. Collect logs from non-OTel applications
2. Collect Kubernetes/system logs automatically
3. Advanced log routing at infrastructure level
4. Legacy application support

**Hybrid Approach (Both):**
```
OTel Apps → OTel Collector → Loki
Non-OTel Apps → Logging Operator → Fluent Bit → Loki
System Logs → Logging Operator → Fluent Bit → Loki
```

This allows:
- Modern apps to use OTel Collector (unified telemetry)
- Legacy apps to use Logging Operator (automatic collection)
- System logs collected automatically

## Platform Dependencies - Helm Chart Installation Locations

For platform-managed deployments, here's where all Helm chart installations are located:

---

## Helm Chart Installation Locations

### 1. OpenTelemetry Collector

**Local Testing Script**: `scripts/setup-observability-stack.sh` (lines 63-79)

**Helm Chart Installation**:
```bash
# From local chart (observability-stack)
helm upgrade --install otel-collector ./chart/observability-stack \
  --namespace observability \
  --wait

# OR from upstream chart (if local chart not available)
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  --wait
```

**Repository**: 
- **Local**: `chart/observability-stack/`
- **Upstream**: `https://open-telemetry.github.io/opentelemetry-helm-charts`
- **Chart Name**: `opentelemetry-collector`

**For Platform Deployment**:
```yaml
# Platform team deploys:
repository: "https://open-telemetry.github.io/opentelemetry-helm-charts"
chart: "opentelemetry-collector"
namespace: "observability"
version: "0.96.0"  # Or latest stable
```

---

### 2. Prometheus + Prometheus Operator

**Local Testing Script**: `scripts/setup-observability-stack.sh` (lines 33-39)
**Monitoring Script**: `scripts/setup-monitoring-helm.sh` (lines 42-53)

**Helm Chart Installation**:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --set prometheus.prometheusSpec.retention=30d \
  --set grafana.adminPassword=admin \
  --wait
```

**Repository**: 
- `https://prometheus-community.github.io/helm-charts`
- **Chart Name**: `kube-prometheus-stack`

**For Platform Deployment**:
```yaml
# Platform team deploys:
repository: "https://prometheus-community.github.io/helm-charts"
chart: "kube-prometheus-stack"
namespace: "observability"
version: "58.0.0"  # Or latest stable
# Includes: Prometheus Operator, Prometheus, Grafana, ServiceMonitor CRDs, AlertManager
```

**Key Values for Platform**:
```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false  # Important: allows ServiceMonitors from any namespace
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    retention: 30d  # Adjust for platform needs
grafana:
  adminPassword: <platform-secure-password>
  persistence:
    enabled: true  # For production
```

---

### 3. Grafana Loki

**Local Testing Script**: `scripts/setup-observability-stack.sh` (lines 41-52)

**Helm Chart Installation**:
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Option 1: Loki Stack (includes Promtail)
helm upgrade --install loki grafana/loki-stack \
  --namespace observability \
  --set loki.enabled=true \
  --set promtail.enabled=true \
  --set grafana.enabled=false \
  --wait

# Option 2: Standalone Loki (recommended for production)
helm upgrade --install loki grafana/loki \
  --namespace observability \
  --wait
```

**Repository**: 
- `https://grafana.github.io/helm-charts`
- **Chart Names**: 
  - `loki-stack` (includes Promtail - for Logging Operator scenarios)
  - `loki` (standalone - for OTel Collector scenarios)

**For Platform Deployment**:
```yaml
# Platform team deploys (Standalone Loki - recommended):
repository: "https://grafana.github.io/helm-charts"
chart: "loki"
namespace: "observability"
version: "6.12.0"  # Or latest stable

# OR with Logging Operator (if needed):
repository: "https://grafana.github.io/helm-charts"
chart: "loki-stack"  # Includes Promtail for Logging Operator
namespace: "observability"
```

**Note**: We use **standalone Loki** because:
- OTel Collector forwards logs directly (no Promtail needed)
- Simpler deployment
- Better for OTLP-based log collection

---

### 4. Grafana Tempo

**Local Testing Script**: `scripts/setup-observability-stack.sh` (lines 54-61)

**Helm Chart Installation**:
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install tempo grafana/tempo \
  --namespace observability \
  --set serviceAccount.create=true \
  --wait
```

**Repository**: 
- `https://grafana.github.io/helm-charts`
- **Chart Name**: `tempo`

**For Platform Deployment**:
```yaml
# Platform team deploys:
repository: "https://grafana.github.io/helm-charts"
chart: "tempo"
namespace: "observability"
version: "1.7.0"  # Or latest stable
```

---

### 5. Grafana

**Local Testing Script**: `scripts/setup-observability-stack.sh` (via kube-prometheus-stack, lines 33-39)

**Helm Chart Installation**:
```bash
# Option 1: Via kube-prometheus-stack (includes Grafana)
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --set grafana.adminPassword=admin \
  --wait

# Option 2: Standalone Grafana
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install grafana grafana/grafana \
  --namespace observability \
  --set adminPassword=admin \
  --set service.type=ClusterIP \
  --wait
```

**Repository**: 
- `https://grafana.github.io/helm-charts`
- **Chart Name**: `grafana`
- **OR**: Included in `kube-prometheus-stack`

**For Platform Deployment**:
```yaml
# Platform team deploys (Standalone - recommended for production):
repository: "https://grafana.github.io/helm-charts"
chart: "grafana"
namespace: "observability"
version: "7.3.0"  # Or latest stable

# OR via kube-prometheus-stack (includes Grafana)
# This is simpler but couples Grafana with Prometheus stack
```

---

### 6. Traefik

**Local Testing Script**: `scripts/setup-traefik-helm.sh` (lines 28-48)

**Helm Chart Installation**:
```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm upgrade --install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443 \
  --set service.type=NodePort \
  --set ingressClass.enabled=true \
  --set ingressClass.isDefaultClass=true \
  --wait --timeout=5m
```

**Repository**: 
- `https://traefik.github.io/charts`
- **Chart Name**: `traefik`

**For Platform Deployment**:
```yaml
# Platform team deploys:
repository: "https://traefik.github.io/charts"
chart: "traefik"
namespace: "traefik-system"
version: "28.0.0"  # Or latest stable
```

---

### 7. Gateway API

**Local Testing Script**: `scripts/setup-gateway-api-helm.sh` (lines 25-47)

**Gateway API CRDs Installation** (not a Helm chart):
```bash
# Install Gateway API CRDs (required first)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Install Traefik with Gateway API support
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm upgrade --install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  --set experimental.kubernetesGateway.enabled=true \
  --wait --timeout=5m
```

**Repository**: 
- Gateway API: **Not a Helm chart** - CRDs installed via kubectl
- Traefik with Gateway API: `https://traefik.github.io/charts`

**For Platform Deployment**:
```yaml
# Platform team deploys Gateway API CRDs (via kubectl/manifest):
# https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Then Traefik with Gateway API support:
repository: "https://traefik.github.io/charts"
chart: "traefik"
namespace: "traefik-system"
version: "28.0.0"
values:
  experimental:
    kubernetesGateway:
      enabled: true
```

---

## Platform Dependencies Documentation

For platform team to deploy separately, create this reference:

### Platform Dependencies Reference

**File**: `docs/PLATFORM_DEPENDENCIES.md` (created below)

This document should list:
- All Helm charts platform team needs to deploy
- Repository URLs
- Chart names
- Recommended versions
- Key configuration values
- Namespace requirements
- Service endpoints applications will reference

---

## Creating Helm Chart Dependencies (Optional)

If you want to declare dependencies in your application chart:

### Option 1: Conditional Dependencies (Recommended)

Create a `Chart.yaml` with optional dependencies:

```yaml
# chart/dm-nkp-gitops-custom-app/Chart.yaml
apiVersion: v2
name: dm-nkp-gitops-custom-app
description: Application with OpenTelemetry observability
type: application
version: 0.1.0
appVersion: "0.1.0"

# Dependencies (marked as optional - platform team deploys separately)
dependencies:
  # These are OPTIONAL - platform team pre-deploys them
  # Declared here for documentation and local testing only
  - name: kube-prometheus-stack
    version: "58.0.0"
    repository: "https://prometheus-community.github.io/helm-charts"
    condition: platform.prometheus.enabled  # Disabled by default
    tags:
      - platform
      - prometheus
    import-values:
      - prometheus
  
  - name: loki
    version: "6.12.0"
    repository: "https://grafana.github.io/helm-charts"
    condition: platform.loki.enabled  # Disabled by default
    tags:
      - platform
      - loki
  
  - name: tempo
    version: "1.7.0"
    repository: "https://grafana.github.io/helm-charts"
    condition: platform.tempo.enabled  # Disabled by default
    tags:
      - platform
      - tempo
  
  - name: grafana
    version: "7.3.0"
    repository: "https://grafana.github.io/helm-charts"
    condition: platform.grafana.enabled  # Disabled by default
    tags:
      - platform
      - grafana
  
  - name: opentelemetry-collector
    version: "0.96.0"
    repository: "https://open-telemetry.github.io/opentelemetry-helm-charts"
    condition: platform.otelCollector.enabled  # Disabled by default
    tags:
      - platform
      - otel-collector

# IMPORTANT: These dependencies are OPTIONAL
# In production, platform team pre-deploys them
# Application chart only references them, doesn't deploy them
```

**Add to values.yaml**:
```yaml
# Platform dependencies (disabled by default - platform team deploys)
platform:
  prometheus:
    enabled: false  # Platform team deploys
  loki:
    enabled: false  # Platform team deploys
  tempo:
    enabled: false  # Platform team deploys
  grafana:
    enabled: false  # Platform team deploys
  otelCollector:
    enabled: false  # Platform team deploys
```

**Usage**:
```bash
# Production: Platform dependencies disabled (default)
helm install app ./chart/dm-nkp-gitops-custom-app

# Local testing: Enable platform dependencies (if needed)
helm install app ./chart/dm-nkp-gitops-custom-app \
  --set platform.prometheus.enabled=true \
  --set platform.loki.enabled=true
```

**However**: This is **NOT recommended** because:
- Dependencies would deploy infrastructure with application (wrong!)
- Platform team manages these separately
- Application chart should only deploy app-specific CRs

### Option 2: Documentation-Based Dependencies (Recommended)

Instead of Helm dependencies, document platform requirements:

**File**: `chart/dm-nkp-gitops-custom-app/PLATFORM_REQUIREMENTS.md`

This documents:
- What platform services are required
- Where to find deployment instructions
- What the application expects (service names, namespaces, labels)
- How to configure application to reference platform services

---

## Summary

### Logging Operator

**Not Used Because:**
- ✅ OTel Collector already handles log collection via OTLP
- ✅ Unified collection for metrics, logs, and traces
- ✅ Application is OpenTelemetry-instrumented
- ✅ Simpler architecture (one collector)

**Would Use When:**
- ❌ Need to collect logs from non-OTel applications
- ❌ Need automatic log collection without code changes
- ❌ Need to collect Kubernetes/system logs
- ❌ Mixed stack (OTel + legacy applications)

### Platform Dependencies Location

All Helm chart installations are in:
- `scripts/setup-observability-stack.sh` - OTel Collector, Prometheus, Loki, Tempo, Grafana
- `scripts/setup-monitoring-helm.sh` - Prometheus + Grafana (kube-prometheus-stack)
- `scripts/setup-traefik-helm.sh` - Traefik
- `scripts/setup-gateway-api-helm.sh` - Gateway API + Traefik

**For platform team reference**: See `docs/PLATFORM_DEPENDENCIES.md` (created below)
