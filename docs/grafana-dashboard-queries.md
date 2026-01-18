# Grafana Dashboard Queries Reference

This document lists all queries used in each panel of the Grafana dashboards for easy verification and troubleshooting.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Label Origins](#label-origins)
- [Metrics Dashboard](#metrics-dashboard)
- [Logs Dashboard](#logs-dashboard)
- [Traces Dashboard](#traces-dashboard)
- [Verification Steps](#verification-steps)

## Architecture Overview

### Complete Observability Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        dm-nkp-gitops-custom-app                             │
│                                                                             │
│   ┌───────────────┐    ┌───────────────┐    ┌───────────────┐              │
│   │   Metrics     │    │    Logs       │    │   Traces      │              │
│   │   (OTel SDK)  │    │  (OTel SDK)   │    │  (OTel SDK)   │              │
│   └───────┬───────┘    └───────┬───────┘    └───────┬───────┘              │
│           │                    │                    │                       │
│           └────────────────────┼────────────────────┘                       │
│                                │ OTLP (gRPC :4317)                          │
└────────────────────────────────┼────────────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                      OpenTelemetry Collector                               │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Receivers:    otlp (gRPC :4317, HTTP :4318)                         │  │
│  │  Processors:   batch, resource (adds job, service.name)              │  │
│  │  Exporters:    prometheus, prometheusremotewrite, otlphttp/loki,     │  │
│  │                otlp/tempo, debug                                     │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────┬──────────────────────┬──────────────────────┬────────────────┘
              │                      │                      │
              ▼                      ▼                      ▼
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│     Prometheus      │  │    Loki 3.0+        │  │       Tempo         │
│  (metrics storage)  │  │  (logs storage)     │  │  (traces storage)   │
└──────────┬──────────┘  └──────────┬──────────┘  └──────────┬──────────┘
           │                        │                        │
           └────────────────────────┼────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │           Grafana             │
                    │  - Metrics Dashboard          │
                    │  - Logs Dashboard             │
                    │  - Traces Dashboard           │
                    └───────────────────────────────┘
```

### Log Collection (Dual Path)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        dm-nkp-gitops-custom-app                             │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  telemetry.LogInfo(ctx, "message")                                  │   │
│   │  → Writes to stdout/stderr (for FluentBit)                          │   │
│   │  → Sends via OTLP (for OTel Collector)                              │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                    │                                │                       │
│                    │ OTLP                           │ stdout/stderr         │
└────────────────────┼────────────────────────────────┼───────────────────────┘
                     │                                │
     ┌───────────────┘                                └───────────────┐
     │                                                                │
     ▼                                                                ▼
┌─────────────────────────────┐                    ┌─────────────────────────────┐
│   OTel Collector            │                    │   Logging Operator          │
│   → otlphttp/loki exporter  │                    │   (FluentBit → Fluentd)     │
│                             │                    │                             │
│   Labels:                   │                    │   Labels:                   │
│   - service_name            │                    │   - namespace               │
│   - severity_text           │                    │   - pod                     │
│   - trace_id                │                    │   - app_kubernetes_io_name  │
└──────────────┬──────────────┘                    └──────────────┬──────────────┘
               │ /otlp/v1/logs                                    │ /loki/api/v1/push
               └───────────────────────┬──────────────────────────┘
                                       │
                                       ▼
                       ┌───────────────────────────────┐
                       │         Loki 3.0+             │
                       │                               │
                       │  Query OTLP logs:             │
                       │  {service_name="..."}         │
                       │                               │
                       │  Query FluentBit logs:        │
                       │  {app_kubernetes_io_name=...} │
                       └───────────────────────────────┘
```

## Label Origins

Understanding where labels come from is crucial for troubleshooting dashboard queries.

### Metrics Labels

Metrics are exported via OpenTelemetry SDK to the OTel Collector, which then exports to Prometheus.

| Label | Source | Example Value |
|-------|--------|---------------|
| `job` | OTel Collector resource processor | `otel-collector` |
| `service_name` | OTel Collector resource processor | `dm-nkp-gitops-custom-app` |
| `method` | Application code (CounterVec) | `GET`, `POST` |
| `status` | Application code (CounterVec) | `200`, `404` |

**Verify metrics labels:**

```bash
# Check metrics in Prometheus
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
curl "http://localhost:9090/api/v1/query?query=http_requests_total" | jq '.data.result[0].metric'
```

### Logs Labels

| Label | Source | Query Example |
|-------|--------|---------------|
| `service_name` | OTLP logs (OTel SDK) | `{service_name="dm-nkp-gitops-custom-app"}` |
| `namespace` | FluentBit (Kubernetes metadata) | `{namespace="default"}` |
| `app_kubernetes_io_name` | FluentBit (Pod labels) | `{app_kubernetes_io_name="dm-nkp-gitops-custom-app"}` |
| `severity_text` | OTLP logs | `INFO`, `ERROR`, `WARN` |
| `detected_level` | Loki auto-detection | `info`, `error`, `warn` |

**Verify logs labels:**

```bash
# Check available labels in Loki
kubectl port-forward -n observability svc/loki-gateway 3100:80
curl "http://localhost:3100/loki/api/v1/labels" | jq '.data'
```

### Traces Labels

| Attribute | Scope | Query Example |
|-----------|-------|---------------|
| `resource.service.name` | Resource | `{ resource.service.name = "dm-nkp-gitops-custom-app" }` |
| `span.http.target` | Span | `{ span.http.target = "/health" }` |
| `span.http.status_code` | Span | `{ span.http.status_code = 200 }` |
| `span.http.method` | Span | `{ span.http.method = "GET" }` |

**Verify traces:**

```bash
# Check traces in Tempo
kubectl port-forward -n observability svc/tempo 3200:3200
curl "http://localhost:3200/api/search?limit=5" | jq '.traces'
```

## Metrics Dashboard

**Dashboard**: `dm-nkp-gitops-custom-app - Metrics`  
**Datasource**: Prometheus  
**UID**: `dm-nkp-custom-app-metrics`

### Panel 1: HTTP Request Rate

```promql
sum(rate(http_requests_total[5m]))
```

**Description**: Total HTTP request rate per second  
**Legend**: `Total Request Rate`

### Panel 2: Active HTTP Connections

```promql
http_active_connections
```

**Description**: Current number of active HTTP connections  
**Type**: Gauge

### Panel 3: HTTP Request Duration (Percentiles)

```promql
# p50
histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# p95
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# p99
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# Average
sum(rate(http_request_duration_seconds_sum[5m])) / sum(rate(http_request_duration_seconds_count[5m]))
```

### Panel 4: HTTP Response Size

```promql
# p50
histogram_quantile(0.50, sum(rate(http_response_size_bytes_bucket[5m])) by (le))

# p90
histogram_quantile(0.90, sum(rate(http_response_size_bytes_bucket[5m])) by (le))

# p99
histogram_quantile(0.99, sum(rate(http_response_size_bytes_bucket[5m])) by (le))
```

### Panel 5: HTTP Requests by Method and Status

```promql
sum by (method, status) (rate(http_requests_by_method_total[5m]))
```

### Panel 6: Business Metrics

```promql
business_metric_value
```

## Logs Dashboard

**Dashboard**: `dm-nkp-gitops-custom-app - Loki Logs (Logging Operator)`  
**Datasource**: Loki  
**UID**: `dm-nkp-loki-operator`

### Panel 1: OTLP Logs (via OTel SDK)

```logql
{service_name="dm-nkp-gitops-custom-app"}
```

**Description**: Logs sent directly from app via OTel SDK → OTel Collector → Loki OTLP endpoint  
**Note**: Requires Loki 3.0+ with OTLP support

### Panel 2: Logging Operator Logs (via FluentBit)

```logql
{namespace="default", app_kubernetes_io_name="dm-nkp-gitops-custom-app"} | json | line_format "{{.message}}"
```

**Description**: Logs collected from stdout/stderr via FluentBit/Fluentd  
**Note**: JSON parsing extracts the actual log message from container log format

### Panel 3: Log Volume by Source

```logql
# OTLP Logs
sum(count_over_time({service_name="dm-nkp-gitops-custom-app"}[1m]))

# FluentBit Logs
sum(count_over_time({namespace="default", app_kubernetes_io_name="dm-nkp-gitops-custom-app"}[1m]))
```

### Panel 4: Log Levels

```logql
# Errors (OTLP + FluentBit)
sum(count_over_time({service_name="dm-nkp-gitops-custom-app"} | detected_level="error" [1m])) 
  or 
sum(count_over_time({namespace="default", app_kubernetes_io_name="dm-nkp-gitops-custom-app"} |~ "\\[ERROR\\]" [1m]))

# Warnings
sum(count_over_time({service_name="dm-nkp-gitops-custom-app"} | detected_level="warn" [1m])) 
  or 
sum(count_over_time({namespace="default", app_kubernetes_io_name="dm-nkp-gitops-custom-app"} |~ "\\[WARN\\]" [1m]))

# Info
sum(count_over_time({service_name="dm-nkp-gitops-custom-app"} | detected_level="info" [1m])) 
  or 
sum(count_over_time({namespace="default", app_kubernetes_io_name="dm-nkp-gitops-custom-app"} |~ "\\[INFO\\]" [1m]))
```

### Panel 5: Error Logs

```logql
# OTLP Errors
{service_name="dm-nkp-gitops-custom-app"} | detected_level="error"

# FluentBit Errors
{namespace="default", app_kubernetes_io_name="dm-nkp-gitops-custom-app"} |~ "\\[ERROR\\]" | json | line_format "{{.message}}"
```

### Panel 6: Warning Logs

```logql
# OTLP Warnings
{service_name="dm-nkp-gitops-custom-app"} | detected_level="warn"

# FluentBit Warnings
{namespace="default", app_kubernetes_io_name="dm-nkp-gitops-custom-app"} |~ "\\[WARN\\]" | json | line_format "{{.message}}"
```

## Traces Dashboard

**Dashboard**: `dm-nkp-gitops-custom-app - Traces`  
**Datasource**: Tempo  
**UID**: `dm-nkp-custom-app-traces`

### Panel 1: All Application Traces

```traceql
{ resource.service.name = "dm-nkp-gitops-custom-app" }
```

**Description**: All traces from the application  
**Limit**: 20 traces

### Panel 2: Root Endpoint Traces (GET /)

```traceql
{ resource.service.name = "dm-nkp-gitops-custom-app" && span.http.target = "/" }
```

### Panel 3: Health Check Traces (/health)

```traceql
{ resource.service.name = "dm-nkp-gitops-custom-app" && span.http.target = "/health" }
```

### Panel 4: Readiness Check Traces (/ready)

```traceql
{ resource.service.name = "dm-nkp-gitops-custom-app" && span.http.target = "/ready" }
```

### Panel 5: Successful Requests (HTTP 200)

```traceql
{ resource.service.name = "dm-nkp-gitops-custom-app" && span.http.status_code = 200 }
```

### Panel 6: Error Requests (HTTP 4xx/5xx)

```traceql
{ resource.service.name = "dm-nkp-gitops-custom-app" && span.http.status_code >= 400 }
```

### Panel 7: Slow Traces (> 50ms)

```traceql
{ resource.service.name = "dm-nkp-gitops-custom-app" } | duration > 50ms
```

## Verification Steps

### 1. Generate Traffic

```bash
# Port forward to the application
kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080 &

# Generate traffic
for i in {1..100}; do
  curl -s http://localhost:8080/ > /dev/null
  curl -s http://localhost:8080/health > /dev/null
  curl -s http://localhost:8080/ready > /dev/null
done
```

### 2. Verify Metrics

```bash
# Port forward to Prometheus
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090

# Test queries
curl "http://localhost:9090/api/v1/query?query=sum(rate(http_requests_total[5m]))" | jq '.data.result[0].value[1]'
curl "http://localhost:9090/api/v1/query?query=http_active_connections" | jq '.data.result[0].value[1]'
```

### 3. Verify Logs

```bash
# Port forward to Loki
kubectl port-forward -n observability svc/loki-gateway 3100:80

# Check OTLP logs (Loki 3.0+)
curl -sG "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={service_name="dm-nkp-gitops-custom-app"}' | jq '.data.result | length'

# Check FluentBit logs
curl -sG "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={app_kubernetes_io_name="dm-nkp-gitops-custom-app"}' | jq '.data.result | length'
```

### 4. Verify Traces

```bash
# Port forward to Tempo
kubectl port-forward -n observability svc/tempo 3200:3200

# Search for traces
curl "http://localhost:3200/api/search?limit=10" | jq '.traces | length'

# Check available service names
curl "http://localhost:3200/api/search/tag/service.name/values" | jq '.tagValues'

# Check available http.target values
curl "http://localhost:3200/api/search/tag/http.target/values" | jq '.tagValues'
```

### 5. Access Grafana

```bash
# Get Grafana password
GRAFANA_PASS=$(kubectl get secret -n observability prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)
echo "Password: $GRAFANA_PASS"

# Port forward to Grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80

# Open in browser: http://localhost:3000
# User: admin / Password: (from above)
```

## Quick Reference Tables

### Metrics Queries (Prometheus)

| Query | Description |
|-------|-------------|
| `sum(rate(http_requests_total[5m]))` | Request rate |
| `http_active_connections` | Active connections |
| `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))` | p95 latency |
| `histogram_quantile(0.50, sum(rate(http_response_size_bytes_bucket[5m])) by (le))` | p50 response size |
| `sum by (method, status) (rate(http_requests_by_method_total[5m]))` | Requests by method/status |
| `business_metric_value` | Business metrics |

### Logs Queries (Loki)

| Query | Description | Source |
|-------|-------------|--------|
| `{service_name="dm-nkp-gitops-custom-app"}` | OTLP logs | OTel SDK |
| `{app_kubernetes_io_name="dm-nkp-gitops-custom-app"}` | Container logs | FluentBit |
| `{...} \| detected_level="error"` | Error logs (OTLP) | Loki detection |
| `{...} \|~ "\\[ERROR\\]"` | Error logs (FluentBit) | Log pattern |

### Traces Queries (Tempo - TraceQL)

| Query | Description |
|-------|-------------|
| `{ resource.service.name = "dm-nkp-gitops-custom-app" }` | All app traces |
| `{ ... && span.http.target = "/" }` | Root endpoint traces |
| `{ ... && span.http.target = "/health" }` | Health check traces |
| `{ ... && span.http.status_code = 200 }` | Successful requests |
| `{ ... && span.http.status_code >= 400 }` | Error requests |
| `{ ... } \| duration > 50ms` | Slow traces |

## Troubleshooting

### No Metrics Data

1. Check OTel Collector is running: `kubectl get pods -n observability -l app.kubernetes.io/managed-by=opentelemetry-operator`
2. Check OTel Collector logs: `kubectl logs -n observability -l app.kubernetes.io/managed-by=opentelemetry-operator`
3. Verify Prometheus is scraping: Check Prometheus targets at `http://localhost:9090/targets`

### No Logs Data

1. **For OTLP logs**: Ensure Loki 3.0+ is installed with OTLP support
2. **For FluentBit logs**: Check Logging Operator: `kubectl get logging,clusterflow,clusteroutput -A`
3. Check Loki labels: `curl "http://localhost:3100/loki/api/v1/labels"`

### No Traces Data

1. Verify Tempo OTLP receiver: `kubectl get svc tempo -n observability -o yaml | grep 4317`
2. Check OTel Collector exporter: Look for `otlp/tempo` in collector config
3. Verify traces exist: `curl "http://localhost:3200/api/search?limit=5"`

---

**Last Updated**: January 2026  
**Dashboard Version**: Latest (Loki 3.0+ with OTLP support)
