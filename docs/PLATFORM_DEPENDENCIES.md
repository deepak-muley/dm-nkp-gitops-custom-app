# Platform Dependencies - Helm Chart Deployment Reference

This document provides the platform engineering team with all Helm chart deployment information needed to pre-deploy services that the application depends on.

## Overview

The application (`dm-nkp-gitops-custom-app`) deploys only **app-specific Custom Resources** that reference pre-deployed platform services. This document lists all platform services that must be deployed by the platform team.

## Platform Services Required

### 1. OpenTelemetry Collector

**Purpose**: Central collection point for metrics, logs, and traces from applications

**Helm Chart Installation**:
```bash
# Add repository
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Install OTel Collector
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  --create-namespace \
  --version 0.96.0 \
  --wait
```

**Repository**: `https://open-telemetry.github.io/opentelemetry-helm-charts`  
**Chart Name**: `opentelemetry-collector`  
**Version**: `0.96.0` (or latest stable)  
**Namespace**: `observability` (or your platform namespace)

**Required Configuration**:
```yaml
# chart/observability-stack/templates/otel-collector-config.yaml shows the configuration
# Platform team should configure OTel Collector with:
# - OTLP receivers (gRPC port 4317, HTTP port 4318)
# - Prometheus exporter (port 8889) for metrics
# - Loki exporter (endpoint: http://loki:3100/loki/api/v1/push) for logs
# - OTLP exporter to Tempo (endpoint: tempo:4317) for traces
```

**Service Endpoints Applications Reference**:
- **OTLP gRPC**: `otel-collector.observability.svc.cluster.local:4317`
- **OTLP HTTP**: `otel-collector.observability.svc.cluster.local:4318`
- **Prometheus Metrics**: `otel-collector.observability.svc.cluster.local:8889/metrics`

**Service Labels** (for ServiceMonitor selection):
```yaml
# Default (adjust based on your platform deployment):
component: otel-collector

# OR platform-specific:
app.kubernetes.io/name: opentelemetry-collector
app.kubernetes.io/component: collector
```

**Installation Script Location**: `scripts/setup-observability-stack.sh` (lines 63-79)

---

### 2. Prometheus + Prometheus Operator

**Purpose**: Metrics storage and scraping ServiceMonitors deployed by applications

**Helm Chart Installation**:
```bash
# Add repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack (includes Prometheus Operator, Prometheus, Grafana, AlertManager)
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

**Repository**: `https://prometheus-community.github.io/helm-charts`  
**Chart Name**: `kube-prometheus-stack`  
**Version**: `58.0.0` (or latest stable)  
**Namespace**: `observability` (or your platform namespace)

**Includes**:
- Prometheus Operator (CRDs: ServiceMonitor, PodMonitor, PrometheusRule)
- Prometheus (metrics database)
- Grafana (visualization - optional, can deploy separately)
- AlertManager (alerts - optional)

**Critical Configuration Values**:
```yaml
prometheus:
  prometheusSpec:
    # IMPORTANT: Allow ServiceMonitors from any namespace
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    retention: 30d  # Adjust for platform retention policy
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: <your-storage-class>
          resources:
            requests:
              storage: 50Gi  # Adjust for platform needs
```

**Service Endpoints Applications Reference**:
- **Prometheus Query API**: `prometheus-kube-prometheus-prometheus.observability.svc.cluster.local:9090`
- **Prometheus Operator Namespace**: `observability` (where ServiceMonitors are deployed)

**Installation Script Location**: 
- `scripts/setup-observability-stack.sh` (lines 33-39)
- `scripts/setup-monitoring-helm.sh` (lines 42-53)

---

### 3. Grafana Loki

**Purpose**: Log aggregation and storage (receives logs from OTel Collector)

**Helm Chart Installation**:
```bash
# Add repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install standalone Loki (recommended - OTel Collector forwards logs directly)
helm upgrade --install loki grafana/loki \
  --namespace observability \
  --create-namespace \
  --version 6.12.0 \
  --wait
```

**Repository**: `https://grafana.github.io/helm-charts`  
**Chart Name**: `loki` (standalone) or `loki-stack` (includes Promtail - if using Logging Operator)  
**Version**: `6.12.0` (or latest stable)  
**Namespace**: `observability` (or your platform namespace)

**Recommended**: Use **standalone `loki`** chart (not `loki-stack`) because:
- OTel Collector forwards logs directly (no Promtail needed)
- Simpler deployment
- Better for OTLP-based log collection

**Service Endpoints Applications Reference**:
- **Loki Push API**: `loki.observability.svc.cluster.local:3100/loki/api/v1/push`
- **Loki Query API**: `loki.observability.svc.cluster.local:3100` (for Grafana)

**OTel Collector Configuration** (in OTel Collector):
```yaml
exporters:
  loki:
    endpoint: http://loki.observability.svc.cluster.local:3100/loki/api/v1/push
    labels:
      resource:
        service.name: "service_name"
        service.namespace: "service_namespace"
```

**Installation Script Location**: `scripts/setup-observability-stack.sh` (lines 41-52)

**Note**: If using Logging Operator (not recommended with OTel Collector), use `loki-stack` chart which includes Promtail.

---

### 4. Grafana Tempo

**Purpose**: Distributed tracing backend (receives traces from OTel Collector)

**Helm Chart Installation**:
```bash
# Add repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Tempo
helm upgrade --install tempo grafana/tempo \
  --namespace observability \
  --create-namespace \
  --version 1.7.0 \
  --set serviceAccount.create=true \
  --wait
```

**Repository**: `https://grafana.github.io/helm-charts`  
**Chart Name**: `tempo`  
**Version**: `1.7.0` (or latest stable)  
**Namespace**: `observability` (or your platform namespace)

**Service Endpoints Applications Reference**:
- **OTLP gRPC**: `tempo.observability.svc.cluster.local:4317`
- **OTLP HTTP**: `tempo.observability.svc.cluster.local:4318`
- **Query API**: `tempo.observability.svc.cluster.local:3200` (for Grafana)

**OTel Collector Configuration** (in OTel Collector):
```yaml
exporters:
  otlp/tempo:
    endpoint: tempo.observability.svc.cluster.local:4317
    tls:
      insecure: true  # Or configure TLS for production
```

**Installation Script Location**: `scripts/setup-observability-stack.sh` (lines 54-61)

---

### 5. Grafana

**Purpose**: Visualization for metrics, logs, and traces

**Helm Chart Installation**:
```bash
# Add repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install standalone Grafana (recommended for production)
helm upgrade --install grafana grafana/grafana \
  --namespace observability \
  --create-namespace \
  --version 7.3.0 \
  --set adminPassword=<platform-secure-password> \
  --set persistence.enabled=true \
  --set persistence.storageClassName=<your-storage-class> \
  --set persistence.size=10Gi \
  --wait
```

**Repository**: `https://grafana.github.io/helm-charts`  
**Chart Name**: `grafana`  
**Version**: `7.3.0` (or latest stable)  
**Namespace**: `observability` (or your platform namespace)

**OR** (Simpler but couples Grafana with Prometheus):
- Included in `kube-prometheus-stack` chart
- If using kube-prometheus-stack, Grafana is already included

**Required Configuration**:
```yaml
grafana:
  adminPassword: <secure-password>  # Set secure password
  persistence:
    enabled: true  # Required for production
    storageClassName: <your-storage-class>
    size: 10Gi
  # Configure dashboard discovery
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'App Dashboards'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        allowUiUpdates: true
        options:
          path: /var/lib/grafana/dashboards
  dashboards:
    default:
      # This allows ConfigMaps with label grafana_dashboard=1 to be discovered
      provider: App Dashboards
```

**Data Sources Configuration** (Platform team should pre-configure):
```yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      access: proxy
      url: http://prometheus-kube-prometheus-prometheus:9090
      isDefault: true
    - name: Loki
      type: loki
      access: proxy
      url: http://loki:3100
    - name: Tempo
      type: tempo
      access: proxy
      url: http://tempo:3200
      jsonData:
        tracesToLogs:
          datasourceUid: loki
```

**Service Endpoints Applications Reference**:
- **Grafana UI**: `grafana.observability.svc.cluster.local:80` (or configured service URL)
- **Namespace for Dashboard ConfigMaps**: `observability` (where applications deploy dashboards)

**Installation Script Location**: 
- `scripts/setup-observability-stack.sh` (via kube-prometheus-stack, lines 33-39)
- `scripts/setup-monitoring-helm.sh` (via kube-prometheus-stack, lines 42-53)

---

### 6. Traefik (Optional - for Ingress)

**Purpose**: Ingress controller for routing traffic to applications

**Helm Chart Installation**:
```bash
# Add repository
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Install Traefik
helm upgrade --install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  --version 28.0.0 \
  --set ingressClass.enabled=true \
  --set ingressClass.isDefaultClass=true \
  --wait --timeout=5m
```

**Repository**: `https://traefik.github.io/charts`  
**Chart Name**: `traefik`  
**Version**: `28.0.0` (or latest stable)  
**Namespace**: `traefik-system` (or your platform namespace)

**For Gateway API Support**:
```bash
# First, install Gateway API CRDs (not a Helm chart)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Then install Traefik with Gateway API support
helm upgrade --install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  --version 28.0.0 \
  --set experimental.kubernetesGateway.enabled=true \
  --wait --timeout=5m
```

**Service Endpoints Applications Reference**:
- **Ingress Controller**: Applications create IngressRoute/HTTPRoute resources
- **Gateway Name**: `traefik` (default) or as configured by platform
- **Gateway Namespace**: `traefik-system` (or platform namespace)

**Installation Script Location**: 
- `scripts/setup-traefik-helm.sh` (lines 28-48)
- `scripts/setup-gateway-api-helm.sh` (lines 25-47) - Gateway API version

---

### 7. Gateway API CRDs (Optional - for Gateway API)

**Purpose**: Kubernetes Gateway API CRDs (not a Helm chart)

**Installation** (via kubectl/manifest):
```bash
# Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Verify CRDs
kubectl get crd gateways.gateway.networking.k8s.io
kubectl get crd httproutes.gateway.networking.k8s.io
```

**Repository**: **Not a Helm chart** - CRDs installed via kubectl  
**Source**: `https://github.com/kubernetes-sigs/gateway-api/releases`  
**Version**: `v1.0.0` (or latest stable)

**Installation Script Location**: `scripts/setup-gateway-api-helm.sh` (lines 25-27)

**Note**: This is a prerequisite for Gateway API support in Traefik (see Traefik section above).

---

## Complete Platform Deployment Command Reference

### Quick Reference: All Platform Services

```bash
# 1. Add all Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add traefik https://traefik.github.io/charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# 2. Install Prometheus Operator + Prometheus + Grafana
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --create-namespace \
  --version 58.0.0 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.retention=30d \
  --wait

# 3. Install Loki (standalone)
helm upgrade --install loki grafana/loki \
  --namespace observability \
  --version 6.12.0 \
  --wait

# 4. Install Tempo
helm upgrade --install tempo grafana/tempo \
  --namespace observability \
  --version 1.7.0 \
  --set serviceAccount.create=true \
  --wait

# 5. Install OpenTelemetry Collector
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  --version 0.96.0 \
  --wait

# 6. Install Traefik (optional - for ingress)
helm upgrade --install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  --version 28.0.0 \
  --set ingressClass.enabled=true \
  --wait

# 7. Install Gateway API CRDs (optional - if using Gateway API)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

---

## Application Chart Expectations

The application chart (`dm-nkp-gitops-custom-app`) expects the following from platform services:

### Service Names and Namespaces

```yaml
# OTel Collector
otel-collector:
  service: "otel-collector.observability.svc.cluster.local"
  namespace: "observability"
  ports:
    otlp-grpc: 4317
    otlp-http: 4318
    prometheus: 8889

# Prometheus
prometheus:
  service: "prometheus-kube-prometheus-prometheus.observability.svc.cluster.local"
  namespace: "observability"
  operatorNamespace: "observability"  # For ServiceMonitor deployment

# Loki
loki:
  service: "loki.observability.svc.cluster.local"
  namespace: "observability"
  port: 3100

# Tempo
tempo:
  service: "tempo.observability.svc.cluster.local"
  namespace: "observability"
  port: 4317  # OTLP gRPC

# Grafana
grafana:
  service: "grafana.observability.svc.cluster.local"
  namespace: "observability"  # For dashboard ConfigMap deployment
  port: 80
```

### Service Labels for ServiceMonitor Selection

Applications deploy ServiceMonitors that select OTel Collector services. Platform team should ensure OTel Collector service has matching labels:

```yaml
# Default labels (adjust based on your deployment):
labels:
  component: otel-collector

# OR platform-specific labels:
labels:
  app.kubernetes.io/name: opentelemetry-collector
  app.kubernetes.io/component: collector
```

Applications configure this via:
```yaml
monitoring:
  serviceMonitor:
    otelCollector:
      selectorLabels:
        component: otel-collector  # Or your platform's labels
```

---

## Configuration Values for Platform Team

### Recommended Production Values

Create a platform values file for each service:

**`platform-values/prometheus-values.yaml`**:
```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false  # Critical!
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    retention: 30d  # Or your retention policy
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: <your-storage-class>
          resources:
            requests:
              storage: 100Gi  # Adjust for scale
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

**`platform-values/loki-values.yaml`**:
```yaml
loki:
  auth_enabled: false  # Or enable authentication
  storage:
    type: s3  # Or local, gcs, azure
    bucketNames:
      chunks: loki-chunks
      ruler: loki-ruler
  schemaConfig:
    configs:
      - from: 2024-01-01
        store: tsdb
        object_store: s3
        schema: v13
        index:
          prefix: index_
          period: 24h
```

**`platform-values/tempo-values.yaml`**:
```yaml
tempo:
  storage:
    trace:
      backend: s3  # Or local, gcs
      s3:
        bucket: tempo-traces
  resources:
    requests:
      memory: 2Gi
      cpu: 1
    limits:
      memory: 4Gi
      cpu: 2
```

**`platform-values/otel-collector-values.yaml`**:
```yaml
# Configure OTel Collector to export to platform services
config:
  exporters:
    prometheus:
      endpoint: "0.0.0.0:8889"
    loki:
      endpoint: http://loki.observability.svc.cluster.local:3100/loki/api/v1/push
    otlp/tempo:
      endpoint: tempo.observability.svc.cluster.local:4317
  service:
    pipelines:
      metrics:
        exporters: [prometheus]
      logs:
        exporters: [loki]
      traces:
        exporters: [otlp/tempo]
```

---

## Platform Deployment Scripts

Platform team can use or adapt these scripts:

### Option 1: Use Existing Scripts (Adapt for Production)

**Source Scripts** (for reference, adapt for production):
- `scripts/setup-observability-stack.sh` - Complete observability stack
- `scripts/setup-monitoring-helm.sh` - Prometheus + Grafana
- `scripts/setup-traefik-helm.sh` - Traefik
- `scripts/setup-gateway-api-helm.sh` - Gateway API + Traefik

**Adaptation for Production**:
- Update namespaces to platform namespaces
- Add production storage configurations
- Configure authentication/TLS
- Add resource limits appropriate for production scale
- Configure retention policies per platform requirements
- Add backup/disaster recovery configurations

### Option 2: Platform-Specific Scripts

Platform team should create their own deployment scripts based on their requirements:

**Example**: `platform-deploy.sh`
```bash
#!/bin/bash
# Platform team deployment script

NAMESPACE="observability"

# Deploy with platform-specific values
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace $NAMESPACE \
  -f platform-values/prometheus-values.yaml

helm upgrade --install loki grafana/loki \
  --namespace $NAMESPACE \
  -f platform-values/loki-values.yaml

helm upgrade --install tempo grafana/tempo \
  --namespace $NAMESPACE \
  -f platform-values/tempo-values.yaml

helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace $NAMESPACE \
  -f platform-values/otel-collector-values.yaml
```

---

## Version Compatibility Matrix

| Component | Chart Version | App Version | Kubernetes Version |
|-----------|--------------|-------------|-------------------|
| OTel Collector | 0.96.0 | 0.96.0 | 1.24+ |
| Prometheus Stack | 58.0.0 | v2.51.1 | 1.24+ |
| Loki | 6.12.0 | 2.9.6 | 1.24+ |
| Tempo | 1.7.0 | 2.4.2 | 1.24+ |
| Grafana | 7.3.0 | 10.4.0 | 1.24+ |
| Traefik | 28.0.0 | v3.0 | 1.24+ |

**Note**: Always check latest stable versions before production deployment.

---

## Application Configuration Reference

Applications will configure these values to reference platform services:

**Application Chart Values** (`chart/dm-nkp-gitops-custom-app/values.yaml`):
```yaml
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

## Checklist for Platform Team

Before applications can deploy, ensure:

- [ ] **OTel Collector** deployed and configured to export to Prometheus, Loki, Tempo
- [ ] **Prometheus** deployed with `serviceMonitorSelectorNilUsesHelmValues=false`
- [ ] **Loki** deployed and accessible at `loki.<namespace>:3100`
- [ ] **Tempo** deployed and accessible at `tempo.<namespace>:4317`
- [ ] **Grafana** deployed with:
  - [ ] Dashboard discovery configured (ConfigMaps with label `grafana_dashboard=1`)
  - [ ] Data sources configured (Prometheus, Loki, Tempo)
  - [ ] Persistent storage enabled
- [ ] **Service Labels** documented for ServiceMonitor selection
- [ ] **Namespaces** documented and communicated to application teams
- [ ] **Service Endpoints** documented (service names, ports)
- [ ] **Storage** configured (persistent volumes, backup strategies)
- [ ] **Resource Limits** set appropriate for production scale
- [ ] **Authentication/TLS** configured (if required)
- [ ] **Monitoring** of platform services themselves (meta-monitoring)

---

## Troubleshooting for Platform Team

### Applications Can't Send Telemetry to OTel Collector

**Check**:
```bash
# Verify OTel Collector service exists
kubectl get svc -n observability -l component=otel-collector

# Verify OTel Collector pods are running
kubectl get pods -n observability -l component=otel-collector

# Check OTel Collector logs
kubectl logs -n observability -l component=otel-collector
```

**Fix**: Ensure OTel Collector is configured to receive OTLP on ports 4317 (gRPC) and 4318 (HTTP).

### ServiceMonitor Not Discovered by Prometheus

**Check**:
```bash
# Verify ServiceMonitor exists
kubectl get servicemonitor -n observability

# Check Prometheus targets
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090/targets
```

**Fix**: Ensure `serviceMonitorSelectorNilUsesHelmValues=false` in Prometheus configuration.

### Grafana Dashboards Not Appearing

**Check**:
```bash
# Verify ConfigMaps exist with correct label
kubectl get configmap -n observability -l grafana_dashboard=1

# Check Grafana dashboard discovery configuration
kubectl get configmap -n observability grafana-dashboard-provider -o yaml
```

**Fix**: Configure Grafana dashboard discovery to read ConfigMaps with label `grafana_dashboard=1`.

---

## Summary

**Platform Team Responsibilities**:
1. Deploy all observability services (OTel Collector, Prometheus, Loki, Tempo, Grafana)
2. Configure services with appropriate storage, resource limits, authentication
3. Document service names, namespaces, labels, endpoints
4. Ensure Prometheus allows ServiceMonitors from application namespaces
5. Configure Grafana dashboard discovery and data sources

**Application Team Responsibilities**:
1. Deploy only application and app-specific CRs (ServiceMonitor, Dashboard ConfigMaps)
2. Configure application to reference platform services via configurable values
3. Ensure ServiceMonitor selector labels match platform's OTel Collector labels
4. Deploy dashboards to platform's Grafana namespace

**Separation of Concerns**: ✅ Platform manages infrastructure, Applications manage app-specific configs.
