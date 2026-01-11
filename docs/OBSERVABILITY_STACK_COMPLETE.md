# Complete Observability Stack Setup

## Overview

This document provides a complete guide to the OpenTelemetry-based observability stack setup with Grafana dashboards for metrics, logs, and traces.

## Architecture

### Production Deployment (Platform Services Pre-deployed)

```
Platform Services (Pre-deployed by Platform Team)
├── OpenTelemetry Collector (observability namespace)
├── Prometheus + Prometheus Operator (observability namespace)
├── Grafana Loki (observability namespace)
├── Grafana Tempo (observability namespace)
└── Grafana (observability namespace)

Application Chart (dm-nkp-gitops-custom-app)
├── Application Deployment (application namespace)
├── ServiceMonitor CR → References pre-deployed OTel Collector
│   └─ Configures Prometheus to scrape OTel Collector's /metrics endpoint
└── Grafana Dashboard ConfigMaps → References pre-deployed Grafana
    ├── Metrics Dashboard (Prometheus data source)
    ├── Logs Dashboard (Loki data source)
    └── Traces Dashboard (Tempo data source)
```

### Local Testing (Complete Stack)

```
Observability Stack Chart (LOCAL TESTING ONLY)
├── OpenTelemetry Collector (observability namespace)
├── Prometheus + Prometheus Operator (observability namespace)
├── Grafana Loki (observability namespace)
├── Grafana Tempo (observability namespace)
├── Grafana (observability namespace)
└── Grafana Dashboard Provider ConfigMap

Application Chart (dm-nkp-gitops-custom-app)
├── Application Deployment (default namespace)
├── ServiceMonitor CR → References OTel Collector from observability-stack
└── Grafana Dashboard ConfigMaps → References Grafana from observability-stack
```

## Components

### 1. OpenTelemetry Collector

**Purpose**: Central collection point for all telemetry data

**Ports**:
- `4317`: OTLP gRPC receiver
- `4318`: OTLP HTTP receiver
- `8889`: Prometheus exporter endpoint

**Pipelines**:
- **Metrics**: OTLP → Batch → Prometheus exporter
- **Logs**: OTLP → Batch → Loki exporter
- **Traces**: OTLP → Batch → Tempo exporter

**Configuration**: `chart/observability-stack/templates/otel-collector-config.yaml`

### 2. Prometheus

**Purpose**: Metrics storage and querying

**Source**: Metrics from OTel Collector (via ServiceMonitor or direct scrape)

**Configuration**: 
- Local testing: Via `observability-stack` chart
- Production: Pre-deployed by platform team
- Scraping: Configured via ServiceMonitor CR deployed by app chart

### 3. Grafana Loki

**Purpose**: Log aggregation and storage

**Source**: Logs from OTel Collector

**Protocol**: Loki push API (`/loki/api/v1/push`)

**Configuration**:
- Local testing: Via `observability-stack` chart
- Production: Pre-deployed by platform team

### 4. Grafana Tempo

**Purpose**: Distributed tracing backend

**Source**: Traces from OTel Collector

**Protocol**: OTLP (gRPC)

**Configuration**:
- Local testing: Via `observability-stack` chart
- Production: Pre-deployed by platform team

### 5. Grafana

**Purpose**: Visualization UI for metrics, logs, and traces

**Data Sources**:
- Prometheus (for metrics)
- Loki (for logs)
- Tempo (for traces)

**Dashboards**:
- Metrics Dashboard (deployed as ConfigMap)
- Logs Dashboard (deployed as ConfigMap)
- Traces Dashboard (deployed as ConfigMap)

**Configuration**:
- Dashboard discovery via ConfigMaps with label `grafana_dashboard=1`
- Data sources configured by platform team or via app chart

## Grafana Dashboards

### Metrics Dashboard (`dashboard-metrics.json`)

**Data Source**: Prometheus

**Panels**:
1. HTTP Request Rate - Total requests per second
2. Active HTTP Connections - Current active connections (Gauge)
3. HTTP Request Duration Percentiles - p50, p95, p99, average
4. HTTP Response Size - Distribution (p50, p90, p99)
5. HTTP Requests by Method and Status - Breakdown by HTTP method and status code
6. Business Metrics - Table showing custom business metrics

**Queries**:
- `sum(rate(http_requests_total[5m]))` - Request rate
- `http_active_connections` - Active connections
- `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))` - p95 duration
- `rate(http_requests_by_method_total[5m])` - Requests by method/status

### Logs Dashboard (`dashboard-logs.json`)

**Data Source**: Loki

**Panels**:
1. Application Logs Stream - Real-time log stream
2. Log Volume - Logs per minute
3. Log Levels - Breakdown by INFO/WARN/ERROR
4. Error Logs - Filtered error log stream

**Queries**:
- `{service_name="dm-nkp-gitops-custom-app"}` - All logs
- `sum(count_over_time({service_name="dm-nkp-gitops-custom-app"}[1m]))` - Log volume
- `{service_name="dm-nkp-gitops-custom-app"} |= "ERROR"` - Error logs

### Traces Dashboard (`dashboard-traces.json`)

**Data Source**: Tempo

**Panels**:
1. Trace Search - Search traces by service name
2. Trace Rate - Traces per second
3. Trace Duration Distribution - Duration histogram
4. Traces by HTTP Route - Breakdown by route
5. Traces by HTTP Status Code - Breakdown by status code

**Queries**:
- `{ service.name = "dm-nkp-gitops-custom-app" }` - All traces
- `{ service.name = "dm-nkp-gitops-custom-app" } | rate()` - Trace rate
- `{ service.name = "dm-nkp-gitops-custom-app" } | duration()` - Duration

## Deployment

### Local Testing (Complete Setup)

**Step 1: Deploy Observability Stack** (LOCAL TESTING ONLY)

```bash
# Deploy observability stack chart
helm upgrade --install observability-stack ./chart/observability-stack \
  --namespace observability \
  --create-namespace \
  --wait

# Or use the setup script
./scripts/setup-observability-stack.sh
```

This deploys:
- OpenTelemetry Collector
- Prometheus (via kube-prometheus-stack)
- Grafana Loki
- Grafana Tempo
- Grafana
- Grafana Dashboard Provider ConfigMap

**Step 2: Deploy Application with Dashboards**

```bash
# Deploy application with local testing values
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  -f ./chart/dm-nkp-gitops-custom-app/values-local-testing.yaml

# Or with explicit values
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  --set opentelemetry.enabled=true \
  --set grafana.dashboards.enabled=true \
  --set grafana.dashboards.namespace=observability \
  --set monitoring.serviceMonitor.enabled=true \
  --set monitoring.serviceMonitor.namespace=observability
```

### Production Deployment

**Only Deploy Application Chart** (Platform services pre-deployed)

```bash
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  -f ./chart/dm-nkp-gitops-custom-app/values-production.yaml \
  --set opentelemetry.collector.endpoint=otel-collector.observability.svc.cluster.local:4317 \
  --set monitoring.serviceMonitor.otelCollector.namespace=observability \
  --set monitoring.serviceMonitor.otelCollector.selectorLabels.app.kubernetes.io/name=opentelemetry-collector \
  --set grafana.dashboards.namespace=observability
```

## App-Specific Custom Resources

### 1. ServiceMonitor

**Template**: `chart/dm-nkp-gitops-custom-app/templates/servicemonitor-otel.yaml`

**Purpose**: Configures Prometheus to scrape metrics from OTel Collector's Prometheus endpoint

**Configuration**:
```yaml
monitoring:
  serviceMonitor:
    enabled: true
    namespace: "observability"  # Prometheus Operator namespace
    interval: 30s
    scrapeTimeout: 10s
    otelCollector:
      namespace: "observability"  # OTel Collector namespace
      selectorLabels:
        component: otel-collector  # Match OTel Collector service labels
      prometheusPort: "prometheus"  # Port name
      prometheusPath: "/metrics"  # Metrics path
```

**Result**: Prometheus automatically discovers and scrapes OTel Collector's `/metrics` endpoint.

### 2. Grafana Dashboard ConfigMaps

**Template**: `chart/dm-nkp-gitops-custom-app/templates/grafana-dashboards.yaml`

**Purpose**: Deploys Grafana dashboards as ConfigMaps for automatic discovery

**Dashboards Deployed**:
- `dashboard-metrics.json` → Metrics Dashboard ConfigMap
- `dashboard-logs.json` → Logs Dashboard ConfigMap
- `dashboard-traces.json` → Traces Dashboard ConfigMap

**Configuration**:
```yaml
grafana:
  dashboards:
    enabled: true
    namespace: "observability"  # Grafana namespace
    folder: "/"  # Grafana folder
```

**Labels/Annotations**:
- Label: `grafana_dashboard=1` (for discovery)
- Annotation: `grafana-folder: "/"` (for folder assignment)

**Result**: Grafana discovers and displays dashboards automatically (if dashboard discovery is configured).

### 3. Grafana Datasources (Optional)

**Template**: `chart/dm-nkp-gitops-custom-app/templates/grafana-datasources.yaml`

**Purpose**: Configures Grafana data sources (only if platform team hasn't configured them)

**Configuration**:
```yaml
grafana:
  datasources:
    enabled: false  # Set to true only if platform hasn't configured
    namespace: "observability"
    prometheus:
      enabled: true
      url: "http://prometheus-kube-prometheus-prometheus:9090"
    loki:
      enabled: true
      url: "http://loki:3100"
    tempo:
      enabled: true
      url: "http://tempo:3200"
```

**Note**: Usually disabled in production - platform team pre-configures datasources.

## Platform Service References

### Configuration for Production

The application chart references pre-deployed platform services via configurable values. Update these for your platform:

#### OpenTelemetry Collector

```yaml
opentelemetry:
  collector:
    endpoint: "otel-collector.observability.svc.cluster.local:4317"  # Adjust for your platform
```

#### Prometheus Operator

```yaml
monitoring:
  serviceMonitor:
    namespace: "observability"  # Where Prometheus Operator is deployed
    otelCollector:
      namespace: "observability"  # Where OTel Collector is deployed
      selectorLabels:
        app.kubernetes.io/name: opentelemetry-collector  # Match your platform's labels
```

#### Grafana

```yaml
grafana:
  dashboards:
    namespace: "observability"  # Where Grafana is deployed
```

## Verification

### Verify Dashboards are Deployed

```bash
# Check Dashboard ConfigMaps
kubectl get configmap -n observability -l grafana_dashboard=1

# Should see:
# dm-nkp-gitops-custom-app-grafana-dashboard-metrics
# dm-nkp-gitops-custom-app-grafana-dashboard-logs
# dm-nkp-gitops-custom-app-grafana-dashboard-traces
```

### Verify ServiceMonitor is Created

```bash
# Check ServiceMonitor
kubectl get servicemonitor -n observability -l app=dm-nkp-gitops-custom-app

# Verify Prometheus is discovering it
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090/targets
# Should see OTel Collector target as UP
```

### Access Dashboards in Grafana

```bash
# Port-forward to Grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80

# Access Grafana
open http://localhost:3000
# Login: admin/admin (or check secret)

# Navigate to: Dashboards → Browse
# Should see:
# - dm-nkp-gitops-custom-app - Metrics
# - dm-nkp-gitops-custom-app - Logs
# - dm-nkp-gitops-custom-app - Traces
```

### Generate Test Data

```bash
# Port-forward to application
kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080

# Generate traffic
for i in {1..50}; do
  curl http://localhost:8080/
  curl http://localhost:8080/health
  curl http://localhost:8080/ready
  sleep 0.5
done

# Check dashboards in Grafana - should see data appearing
```

## Troubleshooting

### Dashboards Not Appearing in Grafana

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
   kubectl describe deployment -n observability prometheus-grafana | grep -A 20 Volume
   ```

4. **Manually import if needed**:
   - Port-forward to Grafana
   - Go to Dashboards → Import
   - Upload dashboard JSON files from `grafana/` directory

### ServiceMonitor Not Working

1. **Check ServiceMonitor is created**:
   ```bash
   kubectl get servicemonitor -n observability -l app=dm-nkp-gitops-custom-app -o yaml
   ```

2. **Verify OTel Collector service matches selector**:
   ```bash
   kubectl get svc -n observability -l component=otel-collector --show-labels
   ```

3. **Check Prometheus targets**:
   ```bash
   kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
   # Open http://localhost:9090/targets
   ```

### No Data in Dashboards

1. **Metrics Dashboard**:
   - Verify application is generating metrics
   - Check Prometheus is scraping OTel Collector
   - Verify metric names match dashboard queries

2. **Logs Dashboard**:
   - Verify application is logging to stdout
   - Check OTel Collector is forwarding to Loki
   - Verify log labels match Loki queries

3. **Traces Dashboard**:
   - Verify application is creating traces
   - Check OTel Collector is forwarding to Tempo
   - Verify service name matches Tempo queries

## Summary

### What's Deployed Where

#### Observability Stack Chart (LOCAL TESTING ONLY)
- ✅ OTel Collector, Prometheus, Loki, Tempo, Grafana
- ✅ Grafana Dashboard Provider ConfigMap
- ❌ **DO NOT USE IN PRODUCTION**

#### Application Chart
- ✅ Application deployment
- ✅ ServiceMonitor CR (references pre-deployed OTel Collector)
- ✅ Grafana Dashboard ConfigMaps (references pre-deployed Grafana)
- ✅ Optional: Grafana Datasources ConfigMap (if platform hasn't configured)

### Key Points

1. **Production**: Platform services pre-deployed → App chart deploys only app-specific CRs
2. **Local Testing**: Observability stack chart deploys services → App chart references them
3. **Dashboards**: Always deployed by app chart as ConfigMaps with proper labels
4. **ServiceMonitor**: Always deployed by app chart to configure Prometheus scraping
5. **Configuration**: All platform service references are configurable via Helm values

### Next Steps

1. **Local Testing**: Follow "Local Testing" deployment steps
2. **Production**: Update values to match your platform's service names and namespaces
3. **Verify**: Check dashboards appear in Grafana and show data
4. **Customize**: Adjust dashboard queries and panels as needed

## Additional Resources

- See `GRAFANA_DASHBOARDS_SETUP.md` for detailed dashboard setup
- See `DEPLOYMENT_GUIDE.md` for deployment scenarios
- See `opentelemetry-workflow.md` for complete workflow documentation
- See `COMPLETE_WORKFLOW.md` for complete deployment workflow
