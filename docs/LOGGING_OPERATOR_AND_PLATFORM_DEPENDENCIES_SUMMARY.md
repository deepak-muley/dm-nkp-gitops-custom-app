# Logging Operator & Platform Dependencies - Complete Summary

## Question 1: Why is Logging Operator NOT Used?

### Short Answer

**Logging Operator is NOT used** because:
- ✅ **OpenTelemetry Collector handles log collection directly** via OTLP
- ✅ **Unified collection** for metrics, logs, and traces (one collector)
- ✅ **Application is OpenTelemetry-instrumented** (exports logs via OTLP)
- ✅ **Simpler architecture** (one collector instead of multiple components)

### Current Log Collection Flow

```
Application (Go)
├── Logs to stdout/stderr
└── OTLP Export (gRPC/HTTP) → OpenTelemetry Collector
                              ↓
                         Loki Exporter
                              ↓
                           Loki (/api/v1/push)
```

**No Logging Operator Needed!** ✅

### When WOULD You Use Logging Operator?

**Use Logging Operator when you have:**

1. **Non-OTel Applications**:
   - Legacy applications without OpenTelemetry instrumentation
   - Third-party applications you can't modify
   - Vendor applications
   - Applications that can't export via OTLP

2. **Automatic Log Collection**:
   - Need to collect logs from ALL pods automatically
   - Don't want to modify application code
   - Want infrastructure-level log collection
   - Need to collect system/Kubernetes logs

3. **Mixed Stack**:
   - Combination of OTel-instrumented apps and legacy apps
   - Different logging formats
   - Need both OTel Collector and Logging Operator

4. **Advanced Infrastructure-Level Routing**:
   - Namespace-based log routing
   - Complex log transformations at infrastructure level
   - Multi-destination routing (dev Loki, prod Loki, S3 archive)
   - Centralized log processing policies

5. **System/Kubernetes Logs**:
   - Need kubelet, kube-proxy, system pod logs
   - Node-level log collection
   - Container runtime logs

**If you need Logging Operator**, install it like this:

```bash
helm repo add banzaicloud-stable https://kubernetes-charts.banzaicloud.com
helm repo update

# Install Logging Operator CRDs
helm upgrade --install logging-operator-crds banzaicloud-stable/logging-operator-crds \
  --namespace logging-system \
  --create-namespace \
  --version 4.5.0 \
  --wait

# Install Logging Operator
helm upgrade --install logging-operator banzaicloud-stable/logging-operator \
  --namespace logging-system \
  --version 4.5.0 \
  --wait
```

Then configure Flow/Output CRs to route logs to Loki.

**However**: For this project with OpenTelemetry-instrumented applications, **Logging Operator is NOT needed**.

---

## Question 2: Where Are Helm Chart Installations?

### Complete Location Reference

All Helm chart installations are located in the `scripts/` directory:

| Service | Repository | Chart Name | Version | Script Location | Line Numbers |
|---------|-----------|-----------|---------|----------------|--------------|
| **OpenTelemetry Collector** | `https://open-telemetry.github.io/opentelemetry-helm-charts` | `opentelemetry-collector` | 0.96.0 | `scripts/setup-observability-stack.sh` | 63-79 |
| **Prometheus + Operator** | `https://prometheus-community.github.io/helm-charts` | `kube-prometheus-stack` | 58.0.0 | `scripts/setup-observability-stack.sh` | 33-39<br>`scripts/setup-monitoring-helm.sh` | 42-53 |
| **Grafana Loki** | `https://grafana.github.io/helm-charts` | `loki` or `loki-stack` | 6.12.0 | `scripts/setup-observability-stack.sh` | 41-52 |
| **Grafana Tempo** | `https://grafana.github.io/helm-charts` | `tempo` | 1.7.0 | `scripts/setup-observability-stack.sh` | 54-61 |
| **Grafana** | `https://grafana.github.io/helm-charts` | `grafana` | 7.3.0 | `scripts/setup-observability-stack.sh` | 33-39<br>(via kube-prometheus-stack) |
| **Traefik** | `https://traefik.github.io/charts` | `traefik` | 28.0.0 | `scripts/setup-traefik-helm.sh` | 28-48 |
| **Gateway API** | N/A (CRDs via kubectl) | N/A + `traefik` | v1.0.0 + 28.0.0 | `scripts/setup-gateway-api-helm.sh` | 25-47 |

### Detailed Installation Locations

#### 1. OpenTelemetry Collector

**Location**: `scripts/setup-observability-stack.sh` (lines 63-79)

```bash
# Add repository
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts || true
helm repo update

# Install from local chart
helm upgrade --install otel-collector ./chart/observability-stack \
  --namespace observability \
  --wait

# OR from upstream chart
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  --wait
```

**Repository**: `https://open-telemetry.github.io/opentelemetry-helm-charts`  
**Chart**: `opentelemetry-collector`  
**Version**: `0.96.0` (or latest stable)

---

#### 2. Prometheus + Prometheus Operator (kube-prometheus-stack)

**Locations**:
- `scripts/setup-observability-stack.sh` (lines 29, 35-39)
- `scripts/setup-monitoring-helm.sh` (lines 32-33, 45-53)

```bash
# Add repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update

# Install kube-prometheus-stack (includes Prometheus Operator, Prometheus, Grafana)
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --set prometheus.prometheusSpec.retention=30d \
  --set grafana.adminPassword=admin \
  --wait
```

**Repository**: `https://prometheus-community.github.io/helm-charts`  
**Chart**: `kube-prometheus-stack`  
**Version**: `58.0.0` (or latest stable)

**CRITICAL Config**: Must set `serviceMonitorSelectorNilUsesHelmValues=false` to allow ServiceMonitors from any namespace!

---

#### 3. Grafana Loki

**Location**: `scripts/setup-observability-stack.sh` (lines 30, 43-52)

```bash
# Add repository
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo update

# Install Loki Stack (includes Promtail - for Logging Operator scenarios)
helm upgrade --install loki grafana/loki-stack \
  --namespace observability \
  --set loki.enabled=true \
  --set promtail.enabled=true \
  --set grafana.enabled=false \
  --wait

# OR standalone Loki (recommended for OTel Collector)
helm upgrade --install loki grafana/loki \
  --namespace observability \
  --wait
```

**Repository**: `https://grafana.github.io/helm-charts`  
**Chart**: `loki` (standalone - recommended) or `loki-stack` (includes Promtail)  
**Version**: `6.12.0` (or latest stable)

**Recommendation**: Use **standalone `loki`** chart (not `loki-stack`) because:
- OTel Collector forwards logs directly (no Promtail needed)
- Simpler deployment
- Better for OTLP-based log collection

---

#### 4. Grafana Tempo

**Location**: `scripts/setup-observability-stack.sh` (lines 30, 56-61)

```bash
# Add repository (already added above)
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo update

# Install Tempo
helm upgrade --install tempo grafana/tempo \
  --namespace observability \
  --set serviceAccount.create=true \
  --wait
```

**Repository**: `https://grafana.github.io/helm-charts`  
**Chart**: `tempo`  
**Version**: `1.7.0` (or latest stable)

---

#### 5. Grafana

**Location**: `scripts/setup-observability-stack.sh` (lines 33-39 - via kube-prometheus-stack)

```bash
# Via kube-prometheus-stack (includes Grafana)
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --set grafana.adminPassword=admin \
  --wait

# OR standalone Grafana
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo update

helm upgrade --install grafana grafana/grafana \
  --namespace observability \
  --set adminPassword=admin \
  --set service.type=ClusterIP \
  --wait
```

**Repository**: `https://grafana.github.io/helm-charts`  
**Chart**: `grafana` (standalone) or included in `kube-prometheus-stack`  
**Version**: `7.3.0` (or latest stable)

---

#### 6. Traefik

**Location**: `scripts/setup-traefik-helm.sh` (lines 30, 41-48)

```bash
# Add repository
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Install Traefik
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

**Repository**: `https://traefik.github.io/charts`  
**Chart**: `traefik`  
**Version**: `28.0.0` (or latest stable)

---

#### 7. Gateway API (with Traefik)

**Location**: `scripts/setup-gateway-api-helm.sh` (lines 36, 41-47)

**Step 1**: Install Gateway API CRDs (not a Helm chart)
```bash
# Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

**Step 2**: Install Traefik with Gateway API support
```bash
# Add repository
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Install Traefik with Gateway API support
helm upgrade --install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  --set experimental.kubernetesGateway.enabled=true \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443 \
  --set service.type=NodePort \
  --wait --timeout=5m
```

**Repository**: 
- Gateway API: **Not a Helm chart** - CRDs via kubectl from `https://github.com/kubernetes-sigs/gateway-api/releases`
- Traefik: `https://traefik.github.io/charts`  
**Chart**: `traefik`  
**Version**: `28.0.0` (Traefik) + `v1.0.0` (Gateway API CRDs)

---

## Complete Platform Deployment Reference

### All Helm Repositories Required

```bash
# Add all repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add traefik https://traefik.github.io/charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts

# If using Logging Operator (not recommended with OTel Collector):
# helm repo add banzaicloud-stable https://kubernetes-charts.banzaicloud.com

helm repo update
```

### All Helm Charts for Platform Deployment

**For Platform Team to Deploy**:

1. **kube-prometheus-stack** (Prometheus + Prometheus Operator + Grafana)
   - Repository: `https://prometheus-community.github.io/helm-charts`
   - Chart: `kube-prometheus-stack`
   - Version: `58.0.0`

2. **loki** (Standalone - for OTel Collector)
   - Repository: `https://grafana.github.io/helm-charts`
   - Chart: `loki`
   - Version: `6.12.0`

3. **tempo**
   - Repository: `https://grafana.github.io/helm-charts`
   - Chart: `tempo`
   - Version: `1.7.0`

4. **opentelemetry-collector**
   - Repository: `https://open-telemetry.github.io/opentelemetry-helm-charts`
   - Chart: `opentelemetry-collector`
   - Version: `0.96.0`

5. **traefik** (Optional - for Ingress)
   - Repository: `https://traefik.github.io/charts`
   - Chart: `traefik`
   - Version: `28.0.0`

6. **Gateway API CRDs** (Optional - for Gateway API)
   - Source: `https://github.com/kubernetes-sigs/gateway-api/releases`
   - Version: `v1.0.0`
   - **Not a Helm chart** - installed via kubectl

### Platform Deployment Script Reference

**Script Location**: `scripts/platform-deploy-reference.sh`

This script shows all platform deployment commands for reference. Platform team should adapt these for production.

**Usage**:
```bash
# Show deployment commands (reference only - adapt for production)
./scripts/platform-deploy-reference.sh
```

---

## Creating Helm Chart Dependencies (For Platform Team Reference)

If you want to create a Helm chart that declares these as dependencies (for documentation only):

**Note**: These dependencies should be **OPTIONAL** and **DISABLED** by default because:
- Platform team deploys these separately
- Application chart should NOT deploy platform infrastructure
- Dependencies are for documentation/reference only

### Option 1: Conditional Dependencies in Chart.yaml (Documentation Only)

```yaml
# chart/dm-nkp-gitops-custom-app/Chart.yaml
apiVersion: v2
name: dm-nkp-gitops-custom-app
description: Application with OpenTelemetry observability
type: application
version: 0.1.0
appVersion: "0.1.0"

# Dependencies (OPTIONAL - platform team deploys separately)
# These are for documentation only - disabled by default
dependencies:
  - name: kube-prometheus-stack
    version: "58.0.0"
    repository: "https://prometheus-community.github.io/helm-charts"
    condition: platform.prometheus.enabled  # Default: false
    tags:
      - platform
      - prometheus
  
  - name: loki
    version: "6.12.0"
    repository: "https://grafana.github.io/helm-charts"
    condition: platform.loki.enabled  # Default: false
    tags:
      - platform
      - loki
  
  - name: tempo
    version: "1.7.0"
    repository: "https://grafana.github.io/helm-charts"
    condition: platform.tempo.enabled  # Default: false
    tags:
      - platform
      - tempo
  
  - name: grafana
    version: "7.3.0"
    repository: "https://grafana.github.io/helm-charts"
    condition: platform.grafana.enabled  # Default: false
    tags:
      - platform
      - grafana
  
  - name: opentelemetry-collector
    version: "0.96.0"
    repository: "https://open-telemetry.github.io/opentelemetry-helm-charts"
    condition: platform.otelCollector.enabled  # Default: false
    tags:
      - platform
      - otel-collector

# IMPORTANT: These dependencies are OPTIONAL and DISABLED by default
# Platform team deploys these separately in production
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

**However**: This is **NOT recommended** because:
- Would deploy infrastructure with application (wrong!)
- Platform team manages these separately
- Application chart should only deploy app-specific CRs

### Option 2: Documentation-Based Dependencies (Recommended)

Instead of Helm dependencies, document platform requirements in:

**File**: `chart/dm-nkp-gitops-custom-app/PLATFORM_REQUIREMENTS.md`

This documents:
- What platform services are required
- Where to find deployment instructions (scripts/ location)
- What the application expects (service names, namespaces, labels)
- How to configure application to reference platform services

**This is the recommended approach!** ✅

---

## Platform Team Deployment Checklist

Before applications can deploy, ensure platform services are deployed:

### Required Services

- [ ] **OpenTelemetry Collector**
  - Repository: `https://open-telemetry.github.io/opentelemetry-helm-charts`
  - Chart: `opentelemetry-collector`
  - Version: `0.96.0`
  - Namespace: `observability`
  - Script: `scripts/setup-observability-stack.sh:63-79`

- [ ] **Prometheus + Prometheus Operator**
  - Repository: `https://prometheus-community.github.io/helm-charts`
  - Chart: `kube-prometheus-stack`
  - Version: `58.0.0`
  - Namespace: `observability`
  - **CRITICAL**: `serviceMonitorSelectorNilUsesHelmValues=false`
  - Scripts: `scripts/setup-observability-stack.sh:33-39`, `scripts/setup-monitoring-helm.sh:42-53`

- [ ] **Grafana Loki** (Standalone)
  - Repository: `https://grafana.github.io/helm-charts`
  - Chart: `loki` (standalone - recommended)
  - Version: `6.12.0`
  - Namespace: `observability`
  - Script: `scripts/setup-observability-stack.sh:41-52`

- [ ] **Grafana Tempo**
  - Repository: `https://grafana.github.io/helm-charts`
  - Chart: `tempo`
  - Version: `1.7.0`
  - Namespace: `observability`
  - Script: `scripts/setup-observability-stack.sh:54-61`

- [ ] **Grafana**
  - Repository: `https://grafana.github.io/helm-charts`
  - Chart: `grafana` (standalone) or included in `kube-prometheus-stack`
  - Version: `7.3.0`
  - Namespace: `observability`
  - Script: `scripts/setup-observability-stack.sh:33-39` (via kube-prometheus-stack)

### Optional Services

- [ ] **Traefik** (for Ingress)
  - Repository: `https://traefik.github.io/charts`
  - Chart: `traefik`
  - Version: `28.0.0`
  - Namespace: `traefik-system`
  - Script: `scripts/setup-traefik-helm.sh:28-48`

- [ ] **Gateway API** (for Gateway API support)
  - Source: `https://github.com/kubernetes-sigs/gateway-api/releases`
  - CRDs: Install via kubectl (not a Helm chart)
  - Traefik: With Gateway API support
  - Script: `scripts/setup-gateway-api-helm.sh:25-47`

---

## Application References Platform Services

The application chart references platform services via configurable values:

### Example: Platform Service References

```yaml
# Application Chart Values (chart/dm-nkp-gitops-custom-app/values.yaml)

opentelemetry:
  collector:
    endpoint: "otel-collector.observability.svc.cluster.local:4317"  # Platform service

monitoring:
  serviceMonitor:
    namespace: "observability"  # Prometheus Operator namespace
    otelCollector:
      namespace: "observability"  # OTel Collector namespace
      selectorLabels:
        component: otel-collector  # Match platform's OTel Collector labels

grafana:
  dashboards:
    namespace: "observability"  # Grafana namespace
```

**Platform team should document**:
- Actual service names and namespaces
- Service labels for selector matching
- Any platform-specific configurations

---

## Summary

### Logging Operator

**Not Used Because**:
- ✅ OTel Collector handles log collection directly via OTLP
- ✅ Unified collection for metrics, logs, and traces
- ✅ Application is OpenTelemetry-instrumented
- ✅ Simpler architecture

**Would Use When**:
- ❌ Mixed stack (OTel + non-OTel applications)
- ❌ Legacy applications without OTel instrumentation
- ❌ Need automatic log collection without code changes
- ❌ Need to collect Kubernetes/system logs
- ❌ Advanced infrastructure-level log routing

### Helm Chart Installation Locations

All Helm chart installations are in `scripts/` directory:

- **Observability Stack**: `scripts/setup-observability-stack.sh` - All observability services
- **Monitoring**: `scripts/setup-monitoring-helm.sh` - Prometheus + Grafana
- **Traefik**: `scripts/setup-traefik-helm.sh` - Traefik
- **Gateway API**: `scripts/setup-gateway-api-helm.sh` - Gateway API + Traefik
- **Platform Reference**: `scripts/platform-deploy-reference.sh` - All deployment commands

### For Platform Team

Use these documents:
- `docs/PLATFORM_DEPENDENCIES.md` - Complete deployment guide
- `docs/HELM_CHART_INSTALLATION_REFERENCE.md` - Quick reference table
- `docs/LOGGING_OPERATOR_AND_PLATFORM_DEPENDENCIES.md` - Detailed explanation
- `scripts/platform-deploy-reference.sh` - Deployment commands reference

### For Application Team

Application chart references platform services via:
- Configurable OTel Collector endpoint
- Configurable ServiceMonitor namespace and selector labels
- Configurable Grafana namespace for dashboards

All platform service references are configurable via Helm values to match your platform deployment.
