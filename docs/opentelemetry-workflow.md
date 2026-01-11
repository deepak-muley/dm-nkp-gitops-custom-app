# OpenTelemetry Observability Stack - Workflow Documentation

## Overview

This application uses OpenTelemetry as a unified collector for logs, metrics, and traces. The telemetry data flows through the OpenTelemetry Collector and is stored in specialized databases, then visualized in Grafana.

## Architecture

```
Application (Go) 
    ↓
    | (OTLP - gRPC/HTTP)
    ↓
OpenTelemetry Collector
    ↓                    ↓                    ↓
    |                    |                    |
Prometheus           Grafana Loki         Grafana Tempo
(Metrics)             (Logs)               (Traces)
    ↓                    ↓                    ↓
    └────────────────────┴────────────────────┘
                         ↓
                   Grafana (Visualization)
```

## Components

### 1. OpenTelemetry Collector
- **Purpose**: Central collection point for all telemetry data
- **Protocol**: OTLP (OpenTelemetry Protocol) over gRPC or HTTP
- **Ports**:
  - `4317`: OTLP gRPC receiver
  - `4318`: OTLP HTTP receiver
  - `8889`: Prometheus exporter endpoint (for metrics)

### 2. Prometheus
- **Purpose**: Metrics storage and querying
- **Source**: Metrics from OTel Collector (scraped from collector's Prometheus endpoint)
- **Configuration**: Via kube-prometheus-stack Helm chart

### 3. Grafana Loki
- **Purpose**: Log aggregation and storage
- **Source**: Logs from OTel Collector
- **Protocol**: Loki push API

### 4. Grafana Tempo
- **Purpose**: Distributed tracing backend
- **Source**: Traces from OTel Collector
- **Protocol**: OTLP

### 5. Grafana
- **Purpose**: Visualization UI for metrics, logs, and traces
- **Data Sources**: Prometheus, Loki, Tempo
- **Access**: Port-forward to `localhost:3000` (admin/admin)

## Application Configuration

### Environment Variables

The application needs these environment variables configured:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317
OTEL_SERVICE_NAME=dm-nkp-gitops-custom-app
OTEL_RESOURCE_ATTRIBUTES=service.name=dm-nkp-gitops-custom-app,service.version=0.1.0
```

### Metrics

The application exports these metrics via OpenTelemetry:

- `http_requests_total` (Counter): Total number of HTTP requests
- `http_requests_by_method_total` (Counter): Requests by HTTP method and status code
- `http_active_connections` (Gauge): Current number of active connections
- `http_request_duration_seconds` (Histogram): Request duration distribution
- `http_response_size_bytes` (Histogram): Response size distribution
- `business_metric_value` (Gauge): Custom business metrics

### Traces

HTTP requests are automatically instrumented with OpenTelemetry tracing middleware. Each request creates a span with:
- HTTP method and URL
- Status code
- Duration
- Response size

### Logs

Logs are output to stdout/stderr and collected by the OTel Collector, which forwards them to Loki.

## Setup Instructions

### Prerequisites

- Kubernetes cluster (or kind/minikube for local testing)
- kubectl configured
- Helm 3.x installed

### Step 1: Set Up Observability Stack

Run the setup script:

```bash
./scripts/setup-observability-stack.sh
```

This script will:
1. Create the `observability` namespace
2. Install Prometheus via kube-prometheus-stack (includes Grafana)
3. Install Loki for log storage
4. Install Tempo for trace storage
5. Install OpenTelemetry Collector
6. Configure Grafana data sources

### Step 2: Deploy Application

Deploy your application with OpenTelemetry configuration:

```bash
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  --set opentelemetry.enabled=true \
  --set opentelemetry.collector.endpoint=otel-collector:4317
```

Or if OTel Collector is in a different namespace:

```bash
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  --set opentelemetry.enabled=true \
  --set opentelemetry.collector.endpoint=otel-collector.observability.svc.cluster.local:4317
```

### Step 3: Access Grafana

Port-forward to Grafana:

```bash
kubectl port-forward -n observability svc/prometheus-grafana 3000:80
```

Access at `http://localhost:3000`:
- Username: `admin`
- Password: `admin`

### Step 4: Import Dashboards (Optional)

You can import pre-configured dashboards for:
- Metrics: Use Prometheus data source
- Logs: Use Loki data source  
- Traces: Use Tempo data source

Example Grafana dashboards:
- [OpenTelemetry Collector Metrics](https://grafana.com/grafana/dashboards/13230)
- [Tempo Traces](https://grafana.com/grafana/dashboards/13639)

## Data Flow

### Metrics Flow

1. Application records metrics using OpenTelemetry SDK
2. Metrics are exported to OTel Collector via OTLP gRPC (port 4317)
3. OTel Collector converts to Prometheus format and exposes on port 8889
4. Prometheus scrapes the collector's `/metrics` endpoint
5. Grafana queries Prometheus for visualization

### Logs Flow

1. Application writes logs to stdout/stderr
2. Kubernetes collects stdout/stderr
3. OTel Collector receives logs via OTLP (or Promtail/Loki can scrape directly)
4. OTel Collector forwards to Loki via Loki push API
5. Grafana queries Loki for log visualization

### Traces Flow

1. Application creates spans for HTTP requests (via otelhttp middleware)
2. Spans are exported to OTel Collector via OTLP gRPC (port 4317)
3. OTel Collector forwards traces to Tempo via OTLP
4. Grafana queries Tempo for trace visualization

## Testing

### Generate Test Traffic

```bash
# Port-forward to your application
kubectl port-forward svc/dm-nkp-gitops-custom-app 8080:8080

# Generate some requests
for i in {1..10}; do
  curl http://localhost:8080/
  sleep 1
done
```

### Verify Metrics in Prometheus

```bash
# Port-forward to Prometheus
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090

# Query metrics
curl 'http://localhost:9090/api/v1/query?query=http_requests_total'
```

### Query Logs in Loki

```bash
# Port-forward to Loki
kubectl port-forward -n observability svc/loki 3100:3100

# Query logs (example)
curl 'http://localhost:3100/loki/api/v1/query_range?query={service_name="dm-nkp-gitops-custom-app"}'
```

### View Traces in Tempo

Traces can be viewed in Grafana using the Tempo data source. Use trace ID from logs or use Tempo's trace search.

## Troubleshooting

### Application not sending telemetry

1. Check environment variables are set correctly:
   ```bash
   kubectl exec -it deployment/dm-nkp-gitops-custom-app -- env | grep OTEL
   ```

2. Check OTel Collector is reachable:
   ```bash
   kubectl exec -it deployment/dm-nkp-gitops-custom-app -- nc -zv otel-collector 4317
   ```

3. Check application logs for errors:
   ```bash
   kubectl logs deployment/dm-nkp-gitops-custom-app
   ```

### OTel Collector not receiving data

1. Check collector logs:
   ```bash
   kubectl logs -n observability deployment/otel-collector
   ```

2. Check collector configuration:
   ```bash
   kubectl get configmap -n observability otel-collector-config -o yaml
   ```

3. Verify collector service is running:
   ```bash
   kubectl get svc -n observability otel-collector
   ```

### Metrics not appearing in Prometheus

1. Check if Prometheus is scraping the collector:
   ```bash
   kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
   # Then visit http://localhost:9090/targets
   ```

2. Verify collector's Prometheus endpoint:
   ```bash
   kubectl port-forward -n observability svc/otel-collector 8889:8889
   curl http://localhost:8889/metrics
   ```

## Backup of Prometheus Code

The original Prometheus metrics implementation has been backed up to:
- `internal/metrics/prometheus_backup/metrics.go.bak`
- `internal/metrics/prometheus_backup/metrics_test.go.bak`

You can reference these files if needed to understand the migration or revert changes.

## Additional Resources

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [OpenTelemetry Go SDK](https://pkg.go.dev/go.opentelemetry.io/otel)
- [OpenTelemetry Collector Documentation](https://opentelemetry.io/docs/collector/)
- [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)

## Summary

This observability stack provides:
- ✅ **Metrics**: Via OpenTelemetry → Prometheus → Grafana
- ✅ **Logs**: Via stdout/stderr → OTel Collector → Loki → Grafana
- ✅ **Traces**: Via OpenTelemetry → OTel Collector → Tempo → Grafana
- ✅ **Unified Collection**: Single OTLP endpoint for all telemetry
- ✅ **Simple Setup**: Helm charts for easy deployment

The migration from Prometheus direct instrumentation to OpenTelemetry provides:
- Standardized telemetry collection
- Vendor-agnostic approach
- Better correlation between metrics, logs, and traces
- Easier integration with multiple backends
