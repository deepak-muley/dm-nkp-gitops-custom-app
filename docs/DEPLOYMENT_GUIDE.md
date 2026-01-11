# Deployment Guide - OpenTelemetry Observability Stack

## Overview

This guide explains how to deploy the application with OpenTelemetry observability in both local testing and production environments.

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                    APPLICATION (Go)                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │ Metrics  │  │  Logs    │  │ Traces   │                  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                  │
│       │             │             │                         │
│       └─────────────┴─────────────┘                         │
│                   │ OTLP (gRPC/HTTP)                         │
└───────────────────┼──────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│         OPEN TELEMETRY COLLECTOR (Platform Service)         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │ Metrics  │  │  Logs    │  │ Traces   │                  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                  │
│       │             │             │                         │
└───────┼─────────────┼─────────────┼──────────────────────────┘
        │             │             │
        ▼             ▼             ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│ Prometheus  │ │    Loki     │ │    Tempo    │
│  (Metrics)  │ │   (Logs)    │ │  (Traces)   │
└──────┬──────┘ └──────┬──────┘ └──────┬──────┘
       │               │               │
       └───────────────┴───────────────┘
                       │
                       ▼
              ┌─────────────────┐
              │     Grafana     │
              │  (Visualization)│
              └─────────────────┘
```

## Deployment Scenarios

### Scenario 1: Local Testing (Development)

**Purpose**: Complete stack for local development and testing

**Components Deployed**:
1. `observability-stack` chart (LOCAL TESTING ONLY) - Deploys all observability services
2. `dm-nkp-gitops-custom-app` chart - Deploys application + app-specific CRs

**Steps**:

```bash
# 1. Deploy observability stack (local testing only)
helm upgrade --install observability-stack ./chart/observability-stack \
  --namespace observability \
  --create-namespace \
  --wait

# 2. Deploy application with local testing values
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  -f ./chart/dm-nkp-gitops-custom-app/values-local-testing.yaml

# 3. Access Grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80
# Open: http://localhost:3000 (admin/admin)
```

### Scenario 2: Production Deployment (Platform Services Pre-deployed)

**Purpose**: Deploy application on production K8s cluster where platform services are already running

**Components Deployed**:
- Only `dm-nkp-gitops-custom-app` chart
- Chart deploys:
  1. Application deployment
  2. ServiceMonitor CR (references pre-deployed OTel Collector)
  3. Grafana Dashboard ConfigMaps (references pre-deployed Grafana)

**Steps**:

```bash
# Deploy application with production values
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  -f ./chart/dm-nkp-gitops-custom-app/values-production.yaml \
  --set opentelemetry.collector.endpoint=otel-collector.observability.svc.cluster.local:4317 \
  --set monitoring.serviceMonitor.otelCollector.namespace=observability \
  --set grafana.dashboards.namespace=observability
```

## App-Specific Custom Resources Deployed

### 1. ServiceMonitor

**Purpose**: Configures Prometheus to scrape metrics from OTel Collector's Prometheus endpoint

**Template**: `templates/servicemonitor-otel.yaml`

**Configuration**:
```yaml
monitoring:
  serviceMonitor:
    enabled: true
    namespace: "observability"  # Prometheus Operator namespace
    otelCollector:
      namespace: "observability"  # OTel Collector namespace
      selectorLabels:
        component: otel-collector  # Adjust for your platform
      prometheusPort: "prometheus"
      prometheusPath: "/metrics"
```

**Result**: Prometheus automatically discovers and scrapes OTel Collector's `/metrics` endpoint.

### 2. Grafana Dashboard ConfigMaps

**Purpose**: Deploys Grafana dashboards for metrics, logs, and traces

**Templates**: `templates/grafana-dashboards.yaml`

**Dashboards**:
- **Metrics Dashboard** (`dashboard-metrics.json`)
  - HTTP Request Rate
  - Active Connections
  - Request Duration Percentiles
  - Response Size
  - Requests by Method/Status
  - Business Metrics

- **Logs Dashboard** (`dashboard-logs.json`)
  - Application Logs Stream
  - Log Volume
  - Log Levels (INFO/WARN/ERROR)
  - Error Logs

- **Traces Dashboard** (`dashboard-traces.json`)
  - Trace Search
  - Trace Rate
  - Trace Duration Distribution
  - Traces by HTTP Route
  - Traces by HTTP Status Code

**Configuration**:
```yaml
grafana:
  dashboards:
    enabled: true
    namespace: "observability"  # Grafana namespace
    folder: "/"  # Grafana folder
```

**Result**: Grafana discovers and displays dashboards automatically (if configured for dashboard discovery).

## Platform Service References

The application chart references pre-deployed platform services via configurable values. Update these based on your platform:

### OpenTelemetry Collector

```yaml
opentelemetry:
  collector:
    endpoint: "otel-collector.observability.svc.cluster.local:4317"
```

**Service Discovery**: The application sends telemetry to this endpoint via OTLP (gRPC).

### Prometheus

**ServiceMonitor Discovery**: Prometheus Operator automatically discovers ServiceMonitors in the configured namespace.

**ServiceMonitor Configuration**:
```yaml
monitoring:
  serviceMonitor:
    namespace: "observability"  # Where Prometheus Operator is deployed
    otelCollector:
      namespace: "observability"  # Where OTel Collector is deployed
      selectorLabels:
        component: otel-collector  # Must match OTel Collector service labels
```

### Grafana

**Dashboard Discovery**: Grafana discovers dashboards from ConfigMaps with label `grafana_dashboard=1`.

**Grafana Configuration** (done by platform team):
```yaml
# Grafana dashboard provider ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-provider
  namespace: observability
data:
  dashboards.yaml: |
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
```

## Values Files

### `values.yaml` (Default)

Default production-ready values with platform service references.

### `values-local-testing.yaml`

For local testing with `observability-stack` chart:
- References locally deployed observability-stack services
- Uses insecure OTLP connection
- Smaller resource limits

### `values-production.yaml`

Example production values:
- References pre-deployed platform services
- Uses TLS for OTLP (if available)
- Production resource limits
- Autoscaling enabled

## Configuration Examples

### Example 1: Local Testing

```bash
# Deploy observability stack first
helm install observability-stack ./chart/observability-stack \
  --namespace observability --create-namespace

# Deploy application
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  -f ./chart/dm-nkp-gitops-custom-app/values-local-testing.yaml
```

### Example 2: Production with Custom Platform Services

```bash
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  --set opentelemetry.collector.endpoint=otel-collector.platform-monitoring.svc.cluster.local:4317 \
  --set monitoring.serviceMonitor.namespace=platform-monitoring \
  --set monitoring.serviceMonitor.otelCollector.namespace=platform-monitoring \
  --set monitoring.serviceMonitor.otelCollector.selectorLabels.app.kubernetes.io/name=opentelemetry-collector \
  --set grafana.dashboards.namespace=platform-monitoring
```

### Example 3: Production with Values File

```bash
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  -f ./chart/dm-nkp-gitops-custom-app/values-production.yaml
```

## Verification

### Verify Application is Sending Telemetry

```bash
# Check application logs
kubectl logs -n production deployment/dm-nkp-gitops-custom-app | grep -i otel

# Should see: "OpenTelemetry metrics initialized with endpoint: ..."
```

### Verify OTel Collector is Receiving Telemetry

```bash
# Check OTel Collector logs
kubectl logs -n observability deployment/otel-collector | grep -i "Received"

# Check OTel Collector metrics endpoint
kubectl port-forward -n observability svc/otel-collector 8889:8889
curl http://localhost:8889/metrics
```

### Verify Prometheus is Scraping

```bash
# Port-forward to Prometheus
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090

# Check targets
open http://localhost:9090/targets
# Should see OTel Collector target as UP

# Query metrics
curl 'http://localhost:9090/api/v1/query?query=http_requests_total'
```

### Verify Grafana Dashboards

```bash
# Port-forward to Grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80

# Access Grafana
open http://localhost:3000
# Login: admin/admin (or check secret)

# Navigate to Dashboards → Browse
# Should see:
#   - dm-nkp-gitops-custom-app - Metrics
#   - dm-nkp-gitops-custom-app - Logs
#   - dm-nkp-gitops-custom-app - Traces
```

### Verify Logs in Loki

```bash
# Check ConfigMaps for dashboards
kubectl get configmap -n observability -l grafana_dashboard=1

# Query logs via Loki API (if exposed)
kubectl port-forward -n observability svc/loki 3100:3100
curl 'http://localhost:3100/loki/api/v1/query_range?query={service_name="dm-nkp-gitops-custom-app"}'
```

### Verify Traces in Tempo

```bash
# Query traces via Tempo API (if exposed)
kubectl port-forward -n observability svc/tempo 3200:3200
curl 'http://localhost:3200/api/traces?service_name=dm-nkp-gitops-custom-app'
```

## Troubleshooting

### ServiceMonitor Not Discovered

1. **Check ServiceMonitor exists**:
   ```bash
   kubectl get servicemonitor -n observability -l app=dm-nkp-gitops-custom-app
   ```

2. **Verify Prometheus Operator is installed**:
   ```bash
   kubectl get crd servicemonitors.monitoring.coreos.com
   ```

3. **Check Prometheus ServiceMonitor discovery**:
   - Port-forward to Prometheus
   - Go to Status → Service Discovery
   - Look for your ServiceMonitor

4. **Verify OTel Collector service labels match selector**:
   ```bash
   kubectl get svc -n observability -l component=otel-collector --show-labels
   ```

### Grafana Dashboards Not Appearing

1. **Check ConfigMaps exist**:
   ```bash
   kubectl get configmap -n observability -l grafana_dashboard=1
   ```

2. **Verify Grafana dashboard discovery is configured**:
   ```bash
   kubectl get configmap -n observability grafana-dashboard-provider -o yaml
   ```

3. **Check Grafana is mounting ConfigMaps**:
   ```bash
   kubectl describe deployment -n observability prometheus-grafana | grep -A 10 Mounts
   ```

4. **Check Grafana logs**:
   ```bash
   kubectl logs -n observability deployment/prometheus-grafana | grep -i dashboard
   ```

### Telemetry Not Flowing

1. **Verify OTel endpoint is reachable**:
   ```bash
   kubectl exec -it deployment/dm-nkp-gitops-custom-app -- \
     nc -zv otel-collector.observability.svc.cluster.local 4317
   ```

2. **Check application environment variables**:
   ```bash
   kubectl exec deployment/dm-nkp-gitops-custom-app -- env | grep OTEL
   ```

3. **Check OTel Collector logs**:
   ```bash
   kubectl logs -n observability deployment/otel-collector
   ```

4. **Verify OTel Collector ConfigMap**:
   ```bash
   kubectl get configmap -n observability otel-collector-config -o yaml
   ```

## Summary

### Local Testing
- Deploy `observability-stack` chart first (LOCAL TESTING ONLY)
- Deploy application chart with `values-local-testing.yaml`
- All services in `observability` namespace

### Production
- Platform services are pre-deployed by platform team
- Deploy only application chart
- Application chart deploys app-specific CRs (ServiceMonitor, Grafana Dashboards)
- All CRs reference pre-deployed platform services via configurable values
- Update values to match your platform's service names, namespaces, and labels

### Key Points
- ✅ **Observability stack chart** = LOCAL TESTING ONLY
- ✅ **Application chart** = Deploys app + app-specific CRs
- ✅ **ServiceMonitor** = Configures Prometheus to scrape OTel Collector
- ✅ **Grafana Dashboards** = Deployed as ConfigMaps with proper labels
- ✅ **Platform Services** = Pre-deployed, referenced via configurable values
