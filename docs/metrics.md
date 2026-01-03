# Metrics Documentation

This document describes the Prometheus metrics exported by dm-nkp-gitops-custom-app.

## Metrics Endpoint

All metrics are exposed at: `http://localhost:9090/metrics` (or configured `METRICS_PORT`)

## Available Metrics

### Counter Metrics

#### `http_requests_total`

Total number of HTTP requests received by the application.

- **Type**: Counter
- **Labels**: None
- **Example**: `http_requests_total 42`

#### `http_requests_by_method_total`

Total number of HTTP requests grouped by method and status code.

- **Type**: CounterVec
- **Labels**:
  - `method`: HTTP method (GET, POST, etc.)
  - `status`: HTTP status code (200, 404, 500, etc.)
- **Example**:

  ```
  http_requests_by_method_total{method="GET",status="200"} 35
  http_requests_by_method_total{method="POST",status="201"} 7
  ```

### Gauge Metrics

#### `http_active_connections`

Current number of active HTTP connections.

- **Type**: Gauge
- **Labels**: None
- **Example**: `http_active_connections 5`

#### `business_metric_value`

Custom business metric value (demo metric).

- **Type**: GaugeVec
- **Labels**:
  - `type`: Metric type identifier
- **Example**: `business_metric_value{type="demo"} 42`

### Histogram Metrics

#### `http_request_duration_seconds`

Distribution of HTTP request durations in seconds.

- **Type**: Histogram
- **Labels**: None
- **Buckets**: Default Prometheus buckets (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10)
- **Example**:

  ```
  http_request_duration_seconds_bucket{le="0.005"} 10
  http_request_duration_seconds_bucket{le="0.01"} 25
  http_request_duration_seconds_sum 0.5
  http_request_duration_seconds_count 100
  ```

### Summary Metrics

#### `http_response_size_bytes`

Distribution of HTTP response sizes in bytes.

- **Type**: Summary
- **Labels**: None
- **Quantiles**: 0.5 (p50), 0.9 (p90), 0.99 (p99)
- **Example**:

  ```
  http_response_size_bytes{quantile="0.5"} 150
  http_response_size_bytes{quantile="0.9"} 200
  http_response_size_bytes{quantile="0.99"} 250
  http_response_size_bytes_sum 15000
  http_response_size_bytes_count 100
  ```

## Prometheus Queries

### Request Rate

```promql
rate(http_requests_total[5m])
```

### Request Rate by Method

```promql
rate(http_requests_by_method_total[5m])
```

### Average Request Duration

```promql
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])
```

### 95th Percentile Request Duration

```promql
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

### Average Response Size

```promql
rate(http_response_size_bytes_sum[5m]) / rate(http_response_size_bytes_count[5m])
```

### Active Connections

```promql
http_active_connections
```

## Grafana Dashboard

A sample Grafana dashboard JSON is available in `docs/grafana-dashboard.json` (to be created).

Key panels:

- Request rate over time
- Request duration percentiles
- Request count by method
- Active connections
- Response size distribution

## Integration with Prometheus Operator

When deployed with ServiceMonitor, Prometheus will automatically discover and scrape these metrics.

ServiceMonitor configuration:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: dm-nkp-gitops-custom-app
spec:
  selector:
    matchLabels:
      app: dm-nkp-gitops-custom-app
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

## Adding Custom Metrics

To add a new metric:

1. Define in `internal/metrics/metrics.go`:

   ```go
   var MyCustomMetric = promauto.NewCounter(prometheus.CounterOpts{
       Name: "my_custom_metric_total",
       Help: "Description of my custom metric",
   })
   ```

2. Use in your code:

   ```go
   metrics.MyCustomMetric.Inc()
   ```

3. Document in this file

## Metric Naming Conventions

Follow Prometheus naming conventions:

- Use `_total` suffix for counters
- Use `_seconds` suffix for durations
- Use `_bytes` suffix for byte sizes
- Use base units (seconds, bytes, not milliseconds, kilobytes)
- Use snake_case for metric names
- Use descriptive names
