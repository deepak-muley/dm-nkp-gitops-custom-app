# Helm Chart Installation Reference - Platform Dependencies

Quick reference for all Helm chart installations that platform team needs to deploy.

## Quick Reference Table

| Service | Repository | Chart Name | Version | Script Location | Namespace |
|---------|-----------|-----------|---------|----------------|-----------|
| **OpenTelemetry Collector** | `https://open-telemetry.github.io/opentelemetry-helm-charts` | `opentelemetry-collector` | 0.96.0 | `scripts/setup-observability-stack.sh:63-79` | `observability` |
| **Prometheus + Operator** | `https://prometheus-community.github.io/helm-charts` | `kube-prometheus-stack` | 58.0.0 | `scripts/setup-observability-stack.sh:33-39`<br>`scripts/setup-monitoring-helm.sh:42-53` | `observability` |
| **Grafana Loki** | `https://grafana.github.io/helm-charts` | `loki` | 6.12.0 | `scripts/setup-observability-stack.sh:41-52` | `observability` |
| **Grafana Tempo** | `https://grafana.github.io/helm-charts` | `tempo` | 1.7.0 | `scripts/setup-observability-stack.sh:54-61` | `observability` |
| **Grafana** | `https://grafana.github.io/helm-charts` | `grafana` | 7.3.0 | `scripts/setup-observability-stack.sh:33-39`<br>(via kube-prometheus-stack) | `observability` |
| **Traefik** | `https://traefik.github.io/charts` | `traefik` | 28.0.0 | `scripts/setup-traefik-helm.sh:28-48` | `traefik-system` |
| **Gateway API** | N/A (CRDs via kubectl) | N/A | v1.0.0 | `scripts/setup-gateway-api-helm.sh:25-27` | N/A |

## Detailed Installation Commands

### 1. OpenTelemetry Collector

**Repository**: `https://open-telemetry.github.io/opentelemetry-helm-charts`  
**Chart**: `opentelemetry-collector`  
**Version**: `0.96.0`  
**Script**: `scripts/setup-observability-stack.sh` (lines 63-79)

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  --create-namespace \
  --version 0.96.0 \
  --wait
```

### 2. Prometheus + Prometheus Operator

**Repository**: `https://prometheus-community.github.io/helm-charts`  
**Chart**: `kube-prometheus-stack`  
**Version**: `58.0.0`  
**Scripts**: 
- `scripts/setup-observability-stack.sh` (lines 33-39)
- `scripts/setup-monitoring-helm.sh` (lines 42-53)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --create-namespace \
  --version 58.0.0 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.retention=30d \
  --wait
```

**Critical Config**: `serviceMonitorSelectorNilUsesHelmValues=false` - Allows ServiceMonitors from any namespace!

### 3. Grafana Loki

**Repository**: `https://grafana.github.io/helm-charts`  
**Chart**: `loki` (standalone) or `loki-stack` (includes Promtail - if using Logging Operator)  
**Version**: `6.12.0`  
**Script**: `scripts/setup-observability-stack.sh` (lines 41-52)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Standalone Loki (recommended for OTel Collector)
helm upgrade --install loki grafana/loki \
  --namespace observability \
  --create-namespace \
  --version 6.12.0 \
  --wait

# OR Loki Stack (if using Logging Operator - not recommended with OTel)
# helm upgrade --install loki grafana/loki-stack \
#   --namespace observability \
#   --set loki.enabled=true \
#   --set promtail.enabled=true \
#   --set grafana.enabled=false \
#   --wait
```

**Recommendation**: Use **standalone `loki`** chart (not `loki-stack`) because:
- OTel Collector forwards logs directly (no Promtail needed)
- Simpler deployment
- Better for OTLP-based log collection

### 4. Grafana Tempo

**Repository**: `https://grafana.github.io/helm-charts`  
**Chart**: `tempo`  
**Version**: `1.7.0`  
**Script**: `scripts/setup-observability-stack.sh` (lines 54-61)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install tempo grafana/tempo \
  --namespace observability \
  --create-namespace \
  --version 1.7.0 \
  --set serviceAccount.create=true \
  --wait
```

### 5. Grafana

**Repository**: `https://grafana.github.io/helm-charts`  
**Chart**: `grafana` (standalone) or included in `kube-prometheus-stack`  
**Version**: `7.3.0`  
**Script**: `scripts/setup-observability-stack.sh` (lines 33-39 - via kube-prometheus-stack)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Standalone Grafana (recommended for production)
helm upgrade --install grafana grafana/grafana \
  --namespace observability \
  --create-namespace \
  --version 7.3.0 \
  --set adminPassword=<secure-password> \
  --set persistence.enabled=true \
  --wait

# OR via kube-prometheus-stack (includes Grafana - simpler but couples Grafana)
# Already included in kube-prometheus-stack deployment above
```

### 6. Traefik

**Repository**: `https://traefik.github.io/charts`  
**Chart**: `traefik`  
**Version**: `28.0.0`  
**Script**: `scripts/setup-traefik-helm.sh` (lines 28-48)

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm upgrade --install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  --version 28.0.0 \
  --set ingressClass.enabled=true \
  --set ingressClass.isDefaultClass=true \
  --wait --timeout=5m
```

### 7. Gateway API (with Traefik)

**Repository**: N/A (CRDs installed via kubectl, then Traefik)  
**Chart**: N/A (CRDs) + `traefik`  
**Version**: `v1.0.0` (CRDs) + `28.0.0` (Traefik)  
**Script**: `scripts/setup-gateway-api-helm.sh` (lines 25-47)

```bash
# Step 1: Install Gateway API CRDs (not a Helm chart)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Step 2: Install Traefik with Gateway API support
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm upgrade --install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  --version 28.0.0 \
  --set experimental.kubernetesGateway.enabled=true \
  --wait --timeout=5m
```

## Logging Operator - Not Used, But When Would You Need It?

### Why We Don't Use Logging Operator

**Current Setup**:
- ✅ OpenTelemetry Collector handles log collection directly
- ✅ Application exports logs via OTLP (OpenTelemetry standard)
- ✅ OTel Collector forwards logs to Loki via Loki exporter
- ✅ Unified collection for metrics, logs, and traces

**No Need For**:
- ❌ Logging Operator (uses Fluent Bit/D)
- ❌ Promtail (OTel Collector forwards directly)
- ❌ Additional log collection infrastructure

### When Would You Use Logging Operator?

**Use Logging Operator when:**

1. **Mixed Application Stack**:
   - Applications without OpenTelemetry instrumentation
   - Legacy applications you can't modify
   - Third-party applications
   - Need automatic log collection without code changes

2. **Automatic Log Collection**:
   - Collect logs from ALL pods automatically
   - System/Kubernetes logs
   - Node-level logs
   - Container runtime logs

3. **Advanced Log Routing**:
   - Namespace-based log routing
   - Complex log transformations at infrastructure level
   - Multi-destination routing (dev Loki, prod Loki, S3 archive)
   - Centralized log processing policies

4. **Infrastructure-Level Log Processing**:
   - Centralized log filtering/parsing
   - Log enrichment at infrastructure level
   - Compliance/audit logging requirements

**Architecture with Logging Operator**:
```
Applications (Mixed Stack)
├── OTel Apps → OTel Collector → Loki (via OTLP)
└── Non-OTel Apps → Logging Operator → Fluent Bit → Loki
                    ↓
              (Automatic collection via DaemonSet)
```

**If You Need Logging Operator**:

```bash
# Add Logging Operator Helm repository
helm repo add banzaicloud-stable https://kubernetes-charts.banzaicloud.com
helm repo update

# Install Logging Operator
helm upgrade --install logging-operator banzaicloud-stable/logging-operator \
  --namespace logging-system \
  --create-namespace \
  --version 4.5.0 \
  --wait

# Install Logging Operator CRDs
helm upgrade --install logging-operator-crds banzaicloud-stable/logging-operator-crds \
  --namespace logging-system \
  --version 4.5.0 \
  --wait
```

**Then configure Flow/Output CRs to route logs to Loki**.

## Platform Deployment Script

For platform team reference, see:
- **Documentation**: `docs/PLATFORM_DEPENDENCIES.md` - Complete deployment guide
- **Script**: `scripts/platform-deploy-reference.sh` - Shows all deployment commands
- **Logging Operator Info**: `docs/LOGGING_OPERATOR_AND_PLATFORM_DEPENDENCIES.md` - When to use Logging Operator

## Summary

### Why Logging Operator is NOT Used

✅ **OpenTelemetry Collector** handles log collection directly via OTLP  
✅ **Unified collection** for metrics, logs, and traces  
✅ **Application is OTel-instrumented** - no need for automatic collection  
✅ **Simpler architecture** - one collector instead of multiple components  

### When Logging Operator WOULD Be Useful

❌ **Mixed stack** (OTel + non-OTel applications)  
❌ **Legacy applications** without OTel instrumentation  
❌ **Automatic log collection** from all pods (including system pods)  
❌ **Advanced log routing** at infrastructure level  

### Helm Chart Installation Locations

All Helm chart installations are in:
- **Observability Stack**: `scripts/setup-observability-stack.sh`
- **Prometheus + Grafana**: `scripts/setup-monitoring-helm.sh`
- **Traefik**: `scripts/setup-traefik-helm.sh`
- **Gateway API**: `scripts/setup-gateway-api-helm.sh`
- **Platform Reference**: `scripts/platform-deploy-reference.sh`

### For Platform Team

Use these documents for platform deployment:
- `docs/PLATFORM_DEPENDENCIES.md` - Complete platform deployment guide
- `docs/HELM_CHART_INSTALLATION_REFERENCE.md` - This document (quick reference)
- `scripts/platform-deploy-reference.sh` - Deployment commands reference
