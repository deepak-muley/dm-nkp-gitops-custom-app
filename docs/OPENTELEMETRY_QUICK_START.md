# OpenTelemetry Quick Start Guide

This guide provides a quick start to using OpenTelemetry with this application.

## What Changed?

### Before (Prometheus Direct)

- Application exported Prometheus metrics directly
- Separate metrics port (9090) with `/metrics` endpoint
- Prometheus scraped the application directly
- No tracing or structured logging

### After (OpenTelemetry)

- Application uses OpenTelemetry SDK for metrics, logs, and traces
- Single OTLP endpoint sends all telemetry to OTel Collector
- Collector forwards to Prometheus (metrics), Loki (logs), Tempo (traces)
- Unified telemetry collection

## Quick Setup (5 Steps)

### 1. Set Up Observability Stack

```bash
# Recommended: Full E2E demo with everything configured
./scripts/e2e-demo-otel.sh

# Or manually deploy the observability stack
./scripts/setup-observability-stack.sh
```

This installs:

- OpenTelemetry Collector (receives OTLP metrics, logs, traces)
- Prometheus (via kube-prometheus-stack) - metrics storage
- Loki 3.0+ (logs storage with native OTLP support)
- Tempo (distributed tracing)
- Grafana (visualization with pre-configured dashboards)

### 2. Deploy Application

```bash
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  --set opentelemetry.enabled=true
```

### 3. Access Grafana

```bash
kubectl port-forward -n observability svc/prometheus-grafana 3000:80
```

Visit: <http://localhost:3000>

- Username: `admin`
- Password: `admin`

### 4. Configure Data Sources in Grafana

Data sources are auto-configured when using `e2e-demo-otel.sh`. If configuring manually:

1. Go to Configuration → Data Sources
2. Add Prometheus: `http://prometheus-kube-prometheus-prometheus:9090`
3. Add Loki: `http://loki-gateway:80` (Loki 3.0+ with OTLP support)
4. Add Tempo: `http://tempo:3200`

### 5. Generate Test Traffic

```bash
kubectl port-forward svc/dm-nkp-gitops-custom-app 8080:8080

# Generate requests
for i in {1..10}; do
  curl http://localhost:8080/
  sleep 1
done
```

## Viewing Data

### Metrics in Grafana

1. Go to Explore → Select Prometheus data source
2. Query: `http_requests_total`
3. Or use pre-built dashboards (import from Grafana.com)

### Logs in Grafana

1. Go to Explore → Select Loki data source
2. Query: `{service_name="dm-nkp-gitops-custom-app"}`
3. View logs in real-time

### Traces in Grafana

1. Go to Explore → Select Tempo data source
2. Search for traces by service name: `dm-nkp-gitops-custom-app`
3. View distributed traces with timing

## Environment Variables

The application automatically uses these environment variables (set by Helm chart):

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317
OTEL_SERVICE_NAME=dm-nkp-gitops-custom-app
OTEL_RESOURCE_ATTRIBUTES=service.name=dm-nkp-gitops-custom-app,service.version=0.1.0
```

## Metrics Exported

- `http_requests_total` - Total HTTP requests
- `http_requests_by_method_total` - Requests by method and status
- `http_active_connections` - Active connections gauge
- `http_request_duration_seconds` - Request duration histogram
- `http_response_size_bytes` - Response size histogram
- `business_metric_value` - Custom business metrics

## Troubleshooting

### Check if telemetry is being sent

```bash
# Check application logs
kubectl logs -n default deployment/dm-nkp-gitops-custom-app | grep -i otel

# Check OTel Collector logs
kubectl logs -n observability -l app.kubernetes.io/managed-by=opentelemetry-operator --tail=50
```

### Verify OTel Collector is reachable

```bash
# From application pod
kubectl exec -it -n default deployment/dm-nkp-gitops-custom-app -- nc -zv otel-collector.observability 4317
```

### Check Prometheus targets

```bash
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit http://localhost:9090/targets
```

### Check Loki logs

```bash
kubectl port-forward -n observability svc/loki-gateway 3100:80
# Check labels: curl http://localhost:3100/loki/api/v1/labels
# Query logs: curl -G http://localhost:3100/loki/api/v1/query --data-urlencode 'query={service_name="dm-nkp-gitops-custom-app"}'
```

### Check Tempo traces

```bash
kubectl port-forward -n observability svc/tempo 3200:3200
# Search traces: curl http://localhost:3200/api/search?limit=5
```

### Run debug script

```bash
./scripts/debug-logs-traces.sh
```

## Backup

Original Prometheus code is backed up in:

- `internal/metrics/prometheus_backup/`

## Full Documentation

See [docs/opentelemetry-workflow.md](opentelemetry-workflow.md) for complete documentation.
