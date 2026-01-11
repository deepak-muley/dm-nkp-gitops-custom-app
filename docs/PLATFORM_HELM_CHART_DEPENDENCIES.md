# Platform Helm Chart Dependencies - Complete Reference

This document provides the platform engineering team with all Helm chart installation locations, repositories, versions, and configurations needed to pre-deploy services that applications depend on.

## Overview

The application (`dm-nkp-gitops-custom-app`) deploys only **app-specific Custom Resources** that reference pre-deployed platform services. Platform team must deploy these services separately before applications can be deployed.

## All Helm Chart Installations - Location Reference

### 1. OpenTelemetry Collector

**Repository**: `https://open-telemetry.github.io/opentelemetry-helm-charts`  
**Chart**: `opentelemetry-collector`  
**Version**: `0.96.0` (or latest stable)  
**Namespace**: `observability` (or platform namespace)

**Installation Location**: `scripts/setup-observability-stack.sh` (lines 63-79)

**Command**:
```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  --create-namespace \
  --version 0.96.0 \
  --wait
```

**Service Endpoints** (applications reference):
- **OTLP gRPC**: `otel-collector.observability.svc.cluster.local:4317`
- **OTLP HTTP**: `otel-collector.observability.svc.cluster.local:4318`
- **Prometheus Metrics**: `otel-collector.observability.svc.cluster.local:8889/metrics`

**Service Labels** (for ServiceMonitor selection):
- Default: `component: otel-collector`
- Platform-specific: `app.kubernetes.io/name: opentelemetry-collector`

---

### 2. Prometheus + Prometheus Operator (kube-prometheus-stack)

**Repository**: `https://prometheus-community.github.io/helm-charts`  
**Chart**: `kube-prometheus-stack`  
**Version**: `58.0.0` (or latest stable)  
**Namespace**: `observability` (or platform namespace)

**Installation Locations**:
- `scripts/setup-observability-stack.sh` (lines 33-39)
- `scripts/setup-monitoring-helm.sh` (lines 42-53)

**Command**:
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

**CRITICAL Configuration**: `serviceMonitorSelectorNilUsesHelmValues=false` - **REQUIRED** to allow ServiceMonitors from any namespace!

**Includes**:
- Prometheus Operator (CRDs: ServiceMonitor, PodMonitor, PrometheusRule)
- Prometheus (metrics database)
- Grafana (visualization - can deploy separately)
- AlertManager (optional)

**Service Endpoints** (applications reference):
- **Prometheus Query API**: `prometheus-kube-prometheus-prometheus.observability.svc.cluster.local:9090`
- **Prometheus Operator Namespace**: `observability` (where ServiceMonitors are deployed)

---

### 3. Grafana Loki

**Repository**: `https://grafana.github.io/helm-charts`  
**Chart**: `loki` (standalone) or `loki-stack` (includes Promtail - for Logging Operator)  
**Version**: `6.12.0` (or latest stable)  
**Namespace**: `observability` (or platform namespace)

**Installation Location**: `scripts/setup-observability-stack.sh` (lines 41-52)

**Command** (Standalone - Recommended for OTel Collector):
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install loki grafana/loki \
  --namespace observability \
  --create-namespace \
  --version 6.12.0 \
  --wait
```

**OR** (Loki Stack - Only if using Logging Operator):
```bash
helm upgrade --install loki grafana/loki-stack \
  --namespace observability \
  --set loki.enabled=true \
  --set promtail.enabled=true \
  --set grafana.enabled=false \
  --wait
```

**Recommendation**: Use **standalone `loki`** chart because:
- OTel Collector forwards logs directly (no Promtail needed)
- Simpler deployment
- Better for OTLP-based log collection

**Service Endpoints** (applications reference via OTel Collector):
- **Loki Push API**: `loki.observability.svc.cluster.local:3100/loki/api/v1/push`
- **Loki Query API**: `loki.observability.svc.cluster.local:3100` (for Grafana)

---

### 4. Grafana Tempo

**Repository**: `https://grafana.github.io/helm-charts`  
**Chart**: `tempo`  
**Version**: `1.7.0` (or latest stable)  
**Namespace**: `observability` (or platform namespace)

**Installation Location**: `scripts/setup-observability-stack.sh` (lines 54-61)

**Command**:
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

**Service Endpoints** (applications reference via OTel Collector):
- **OTLP gRPC**: `tempo.observability.svc.cluster.local:4317`
- **OTLP HTTP**: `tempo.observability.svc.cluster.local:4318`
- **Query API**: `tempo.observability.svc.cluster.local:3200` (for Grafana)

---

### 5. Grafana

**Repository**: `https://grafana.github.io/helm-charts`  
**Chart**: `grafana` (standalone) or included in `kube-prometheus-stack`  
**Version**: `7.3.0` (or latest stable)  
**Namespace**: `observability` (or platform namespace)

**Installation Locations**:
- `scripts/setup-observability-stack.sh` (lines 33-39 - via kube-prometheus-stack)
- `scripts/setup-monitoring-helm.sh` (lines 42-53 - via kube-prometheus-stack)

**Command** (Standalone - Recommended for Production):
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install grafana grafana/grafana \
  --namespace observability \
  --create-namespace \
  --version 7.3.0 \
  --set adminPassword=<secure-password> \
  --set persistence.enabled=true \
  --set persistence.storageClassName=<your-storage-class> \
  --set persistence.size=10Gi \
  --wait
```

**OR** (Via kube-prometheus-stack - Simpler but couples Grafana with Prometheus):
- Already included in `kube-prometheus-stack` deployment above

**Service Endpoints** (applications reference):
- **Grafana UI**: `grafana.observability.svc.cluster.local:80`
- **Dashboard Namespace**: `observability` (where applications deploy dashboard ConfigMaps)

---

### 6. Traefik

**Repository**: `https://traefik.github.io/charts`  
**Chart**: `traefik`  
**Version**: `28.0.0` (or latest stable)  
**Namespace**: `traefik-system` (or platform namespace)

**Installation Location**: `scripts/setup-traefik-helm.sh` (lines 28-48)

**Command**:
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

**Service Endpoints** (applications reference):
- Applications create IngressRoute/HTTPRoute resources
- Gateway Name: `traefik` (default) or as configured
- Gateway Namespace: `traefik-system` (or platform namespace)

---

### 7. Gateway API (with Traefik)

**Repository**: N/A (CRDs via kubectl, then Traefik Helm chart)  
**Chart**: N/A (CRDs) + `traefik` (with Gateway API support)  
**Version**: `v1.0.0` (CRDs) + `28.0.0` (Traefik)  
**Namespace**: N/A (CRDs) + `traefik-system` (Traefik)

**Installation Location**: `scripts/setup-gateway-api-helm.sh` (lines 25-47)

**Command** (Step 1: Gateway API CRDs - Not a Helm chart):
```bash
# Install Gateway API CRDs (not a Helm chart)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Verify CRDs
kubectl get crd gateways.gateway.networking.k8s.io
kubectl get crd httproutes.gateway.networking.k8s.io
```

**Command** (Step 2: Traefik with Gateway API support):
```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm upgrade --install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  --version 28.0.0 \
  --set experimental.kubernetesGateway.enabled=true \
  --wait --timeout=5m
```

**Source** (for CRDs): `https://github.com/kubernetes-sigs/gateway-api/releases`

---

## Complete Platform Deployment Reference Script

**Script Location**: `scripts/platform-deploy-reference.sh`

This script shows all platform deployment commands for reference. Platform team should adapt these for production.

**Usage**:
```bash
# Show deployment commands (does not deploy, just shows commands)
./scripts/platform-deploy-reference.sh
```

---

## Platform Values Files (Production Configurations)

Create these values files for production deployment:

### `platform-values/otel-collector-values.yaml`

```yaml
# OpenTelemetry Collector Platform Configuration
config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
  processors:
    batch:
      timeout: 1s
      send_batch_size: 1024
  exporters:
    prometheus:
      endpoint: "0.0.0.0:8889"
    loki:
      endpoint: http://loki.observability.svc.cluster.local:3100/loki/api/v1/push
      labels:
        resource:
          service.name: "service_name"
          service.namespace: "service_namespace"
    otlp/tempo:
      endpoint: tempo.observability.svc.cluster.local:4317
      tls:
        insecure: true  # Configure TLS for production
  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [batch]
        exporters: [otlp/tempo]
      metrics:
        receivers: [otlp]
        processors: [batch]
        exporters: [prometheus]
      logs:
        receivers: [otlp]
        processors: [batch]
        exporters: [loki]

# Resource limits for production
resources:
  limits:
    cpu: 2000m
    memory: 2Gi
  requests:
    cpu: 1000m
    memory: 1Gi

# Service labels (for ServiceMonitor selection)
service:
  labels:
    component: otel-collector
    # OR platform-specific:
    # app.kubernetes.io/name: opentelemetry-collector
```

### `platform-values/prometheus-values.yaml`

```yaml
# Prometheus Platform Configuration
prometheus:
  prometheusSpec:
    # CRITICAL: Allow ServiceMonitors from any namespace
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    
    # Retention policy
    retention: 30d  # Adjust for platform needs
    
    # Storage configuration
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: <your-storage-class>
          resources:
            requests:
              storage: 100Gi  # Adjust for scale
    
    # Resource limits
    resources:
      requests:
        memory: 8Gi
        cpu: 2
      limits:
        memory: 16Gi
        cpu: 4

grafana:
  adminPassword: <secure-password-from-secret>
  persistence:
    enabled: true
    storageClassName: <your-storage-class>
    size: 10Gi
```

### `platform-values/loki-values.yaml`

```yaml
# Loki Platform Configuration
loki:
  # Storage backend (s3, gcs, azure, local)
  storage:
    type: s3  # Or local for dev
    bucketNames:
      chunks: loki-chunks
      ruler: loki-ruler
  
  # Schema configuration
  schemaConfig:
    configs:
      - from: 2024-01-01
        store: tsdb
        object_store: s3
        schema: v13
        index:
          prefix: index_
          period: 24h
  
  # Resource limits
  resources:
    requests:
      memory: 4Gi
      cpu: 2
    limits:
      memory: 8Gi
      cpu: 4
```

### `platform-values/tempo-values.yaml`

```yaml
# Tempo Platform Configuration
tempo:
  # Storage backend (s3, gcs, azure, local)
  storage:
    trace:
      backend: s3  # Or local for dev
      s3:
        bucket: tempo-traces
  
  # Resource limits
  resources:
    requests:
      memory: 2Gi
      cpu: 1
    limits:
      memory: 4Gi
      cpu: 2
```

---

## Platform Deployment Command Reference

For platform team to deploy all services:

```bash
# Set namespace
NAMESPACE="observability"

# Add all repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add traefik https://traefik.github.io/charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Create namespace
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# 1. Prometheus + Prometheus Operator + Grafana
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace $NAMESPACE \
  --version 58.0.0 \
  -f platform-values/prometheus-values.yaml \
  --wait

# 2. Loki (Standalone)
helm upgrade --install loki grafana/loki \
  --namespace $NAMESPACE \
  --version 6.12.0 \
  -f platform-values/loki-values.yaml \
  --wait

# 3. Tempo
helm upgrade --install tempo grafana/tempo \
  --namespace $NAMESPACE \
  --version 1.7.0 \
  -f platform-values/tempo-values.yaml \
  --wait

# 4. OpenTelemetry Collector
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace $NAMESPACE \
  --version 0.96.0 \
  -f platform-values/otel-collector-values.yaml \
  --wait

# 5. Traefik (Optional - for Ingress)
TRAEFIK_NAMESPACE="traefik-system"
kubectl create namespace $TRAEFIK_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install traefik traefik/traefik \
  --namespace $TRAEFIK_NAMESPACE \
  --version 28.0.0 \
  --set ingressClass.enabled=true \
  --set ingressClass.isDefaultClass=true \
  --wait

# 6. Gateway API CRDs (Optional - if using Gateway API)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Then enable Gateway API in Traefik
helm upgrade traefik traefik/traefik \
  --namespace $TRAEFIK_NAMESPACE \
  --reuse-values \
  --set experimental.kubernetesGateway.enabled=true \
  --wait
```

---

## Application Configuration Reference

Applications configure these values to reference platform services:

### OTel Collector Reference

```yaml
# Application Chart Values
opentelemetry:
  collector:
    endpoint: "otel-collector.observability.svc.cluster.local:4317"  # Platform service
```

**Adjust for platform**: Update namespace and service name based on your platform deployment.

### Prometheus ServiceMonitor Reference

```yaml
# Application Chart Values
monitoring:
  serviceMonitor:
    namespace: "observability"  # Prometheus Operator namespace
    otelCollector:
      namespace: "observability"  # OTel Collector namespace
      selectorLabels:
        component: otel-collector  # Match platform's OTel Collector labels
```

**Adjust for platform**: Update namespace and selector labels to match your platform's OTel Collector service labels.

### Grafana Dashboard Reference

```yaml
# Application Chart Values
grafana:
  dashboards:
    namespace: "observability"  # Grafana namespace
    folder: "/"  # Grafana folder
```

**Adjust for platform**: Update namespace based on where Grafana is deployed.

---

## Summary

### Logging Operator

**Not Used Because**:
- ✅ OTel Collector handles log collection directly via OTLP
- ✅ Unified collection for metrics, logs, and traces
- ✅ Application is OTel-instrumented
- ✅ Simpler architecture

**Would Use When**:
- ❌ Mixed stack (OTel + non-OTel applications)
- ❌ Legacy applications without OTel instrumentation
- ❌ Need automatic log collection without code changes
- ❌ Need to collect Kubernetes/system logs

### Helm Chart Installation Locations

All Helm chart installations are in:
- **Observability Stack**: `scripts/setup-observability-stack.sh`
- **Prometheus + Grafana**: `scripts/setup-monitoring-helm.sh`
- **Traefik**: `scripts/setup-traefik-helm.sh`
- **Gateway API**: `scripts/setup-gateway-api-helm.sh`
- **Platform Reference**: `scripts/platform-deploy-reference.sh`

### Platform Team Reference

Use these documents for platform deployment:
- `docs/PLATFORM_DEPENDENCIES.md` - Complete deployment guide
- `docs/HELM_CHART_INSTALLATION_REFERENCE.md` - Quick reference table
- `docs/LOGGING_OPERATOR_AND_PLATFORM_DEPENDENCIES.md` - Logging Operator explanation
- `scripts/platform-deploy-reference.sh` - Deployment commands reference

### Application Team Reference

Use these values to configure application references:
- OTel Collector endpoint: `otel-collector.<platform-namespace>.svc.cluster.local:4317`
- Prometheus Operator namespace: `<platform-namespace>` (for ServiceMonitor deployment)
- Grafana namespace: `<platform-namespace>` (for dashboard ConfigMap deployment)
- OTel Collector service labels: Configure via `monitoring.serviceMonitor.otelCollector.selectorLabels`
