# Observability Setup - Standard Configuration Guide

This document describes the standard observability setup for applications using OpenTelemetry, Prometheus, Loki, and Tempo. These settings can be replicated across multiple applications.

## Overview

The observability stack consists of:

- **OpenTelemetry Collector**: Receives telemetry data (metrics, logs, traces) from applications
- **Prometheus**: Stores and queries metrics
- **Loki**: Stores and queries logs (supports both simple and distributed/microservice deployments)
- **Tempo**: Stores and queries traces
- **Grafana**: Visualizes metrics, logs, and traces

## Architecture

```
Application
    │
    ├─→ Metrics (OTLP) ──┐
    ├─→ Logs (stdout/stderr) ──┤
    └─→ Traces (OTLP) ────┘
                              │
                              ▼
                    OpenTelemetry Collector
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
    Prometheus            Loki                 Tempo
    (Metrics)          (Logs)              (Traces)
```

## Standard Configuration

### 1. OpenTelemetry Collector Configuration

#### Receivers

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
```

#### Processors

```yaml
processors:
  batch: {}
  resource:
    attributes:
      - key: job
        value: otel-collector
        action: upsert
```

**Note**: Do NOT override `service.name` in the resource processor for traces, as it will overwrite the application's service name.

#### Exporters

**Metrics Exporters:**

```yaml
exporters:
  prometheusremotewrite:
    endpoint: http://prometheus-kube-prometheus-prometheus.observability.svc.cluster.local:9090/api/v1/write
  prometheus:
    endpoint: 0.0.0.0:8889
```

**Logs Exporters:**

```yaml
exporters:
  otlphttp/loki:
    endpoint: http://loki-loki-distributed-gateway.observability.svc.cluster.local:80/otlp
```

**Traces Exporters:**

```yaml
exporters:
  otlp/tempo:
    endpoint: tempo.observability.svc.cluster.local:4317
    tls:
      insecure: true
```

#### Service Pipelines

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [otlp/tempo]
    metrics:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [prometheusremotewrite, prometheus]
    logs:
      receivers: [otlp]
      processors: [batch, resource]
      exporters: [otlphttp/loki, debug]
```

### 2. Prometheus Configuration

#### Enable Remote Write Receiver

Prometheus must have remote write receiver enabled to accept metrics from OTel Collector:

```yaml
prometheus:
  prometheusSpec:
    remoteWriteReceiver:
      enabled: true
```

#### ServiceMonitor for OTel Collector

Create a ServiceMonitor to scrape the OTel Collector's Prometheus exporter:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: otel-collector
  namespace: observability
spec:
  selector:
    matchLabels:
      app.kubernetes.io/managed-by: opentelemetry-operator
  endpoints:
  - port: prometheus
    interval: 30s
    path: /metrics
    relabelings:
    - action: replace
      targetLabel: job
      replacement: otel-collector
```

### 3. Loki Configuration

#### Compatibility with Loki Microservice/Distributed

**✅ Fully Compatible**: All configurations work with both:

- **Loki Simple Scalable** (single binary)
- **Loki Distributed/Microservice** (distributed components)

#### Endpoint Configuration

**For Loki Distributed/Microservice:**

```yaml
endpoint: http://loki-loki-distributed-gateway.observability.svc.cluster.local:80/otlp
```

**For Loki Simple Scalable:**

```yaml
endpoint: http://loki.observability.svc.cluster.local:3100/otlp
```

**For Custom Loki Deployment:**

```yaml
endpoint: http://<loki-service-name>.<namespace>.svc.cluster.local:<port>/otlp
```

#### OTLP Support

Loki natively supports OTLP ingestion. The OTLP HTTP exporter is the recommended approach (the deprecated `loki` exporter should not be used).

**Important**: Ensure Loki has OTLP endpoint enabled (default in Loki 2.9+).

### 4. Tempo Configuration

#### Standard Endpoint

```yaml
endpoint: tempo.observability.svc.cluster.local:4317
tls:
  insecure: true  # Set to false for production with TLS
```

### 5. Grafana Datasources

#### Prometheus Datasource

```yaml
name: Prometheus
type: prometheus
url: http://prometheus-kube-prometheus-prometheus.observability.svc.cluster.local:9090
access: proxy
```

#### Loki Datasource

```yaml
name: Loki
type: loki
url: http://loki-loki-distributed-gateway.observability.svc.cluster.local:80
access: proxy
```

**Note**: For Loki Simple Scalable, use `http://loki.observability.svc.cluster.local:3100`

#### Tempo Datasource

```yaml
name: Tempo
type: tempo
url: http://tempo.observability.svc.cluster.local:3200
access: proxy
```

## Application Setup

### 1. Environment Variables

```bash
# OpenTelemetry Configuration
OTEL_SERVICE_NAME=your-app-name
OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector-collector.observability.svc.cluster.local:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

### 2. Application Logging

**Current Approach (stdout/stderr):**

- Application logs to stdout/stderr using standard logging
- Requires log collection agent (Grafana Agent, Fluent Bit) to collect and send to Loki

**Alternative Approach (OTLP Logs):**

- Application sends logs via OTLP to OTel Collector
- OTel Collector forwards to Loki via `otlphttp/loki` exporter
- No log collection agent needed

### 3. Metrics Export

- Application sends metrics via OTLP to OTel Collector
- OTel Collector exports to Prometheus (both remote write and scrape endpoint)
- Prometheus scrapes OTel Collector's `/metrics` endpoint

### 4. Traces Export

- Application sends traces via OTLP to OTel Collector
- OTel Collector exports to Tempo

## Replicating to Another Application

### Step 1: Configure Application

1. Set environment variables:

   ```bash
   OTEL_SERVICE_NAME=your-new-app-name
   OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector-collector.observability.svc.cluster.local:4317
   ```

2. Initialize OpenTelemetry SDK in your application:
   - Metrics: Send via OTLP
   - Traces: Send via OTLP
   - Logs: Either stdout/stderr (with log collector) or OTLP

### Step 2: OTel Collector (Already Configured)

The OTel Collector is shared across all applications. No changes needed unless:

- You need custom processors for specific applications
- You need different exporters

### Step 3: Prometheus (Already Configured)

Prometheus automatically discovers metrics from OTel Collector. No changes needed.

### Step 4: Loki (Platform Managed)

**For Loki Distributed/Microservice:**

- Endpoint: `http://loki-loki-distributed-gateway.observability.svc.cluster.local:80/otlp`
- Works with all Loki microservice components (gateway, distributor, ingester, querier, etc.)

**For Loki Simple Scalable:**

- Endpoint: `http://loki.observability.svc.cluster.local:3100/otlp`

**Compatibility Notes:**

- ✅ OTLP HTTP exporter works with both architectures
- ✅ Service names are the same (gateway handles routing)
- ✅ No code changes needed when switching between architectures

### Step 5: Tempo (Already Configured)

Tempo is shared across all applications. No changes needed.

### Step 6: Grafana Dashboards

Create application-specific dashboards:

- Metrics: Query Prometheus with `job="otel-collector"` and filter by `service_name`
- Logs: Query Loki with `{service_name="your-app-name"}`
- Traces: Query Tempo with `service.name="your-app-name"`

## Compatibility Matrix

| Component | Simple Scalable | Distributed/Microservice | Notes |
|-----------|----------------|-------------------------|-------|
| **Loki** | ✅ Compatible | ✅ Compatible | Use gateway service for distributed |
| **Prometheus** | ✅ Compatible | ✅ Compatible | No differences |
| **Tempo** | ✅ Compatible | ✅ Compatible | No differences |
| **OTel Collector** | ✅ Compatible | ✅ Compatible | Same configuration |
| **Grafana** | ✅ Compatible | ✅ Compatible | Same datasource config |

## Key Points for Loki Microservice/Distributed

1. **Service Name**: Always use the gateway service:
   - `loki-loki-distributed-gateway` (for distributed)
   - `loki` (for simple scalable)

2. **Port**:
   - Gateway: Port 80 (HTTP)
   - Simple: Port 3100

3. **OTLP Endpoint**:
   - `/otlp` path works for both architectures
   - Gateway handles routing to backend components

4. **No Code Changes**: Application code doesn't need changes when switching Loki architectures

## Troubleshooting

### No Metrics in Prometheus

- Check OTel Collector is running: `kubectl get pods -n observability -l app.kubernetes.io/managed-by=opentelemetry-operator`
- Check ServiceMonitor exists: `kubectl get servicemonitor otel-collector -n observability`
- Verify Prometheus remote write receiver is enabled

### No Logs in Loki

- **If using stdout/stderr**: Deploy log collection agent (Grafana Agent/Fluent Bit)
- **If using OTLP logs**: Check OTel Collector logs exporter configuration
- Verify Loki OTLP endpoint is accessible: `curl http://loki-gateway:80/otlp`

### No Traces in Tempo

- Check OTel Collector traces pipeline configuration
- Verify Tempo service is accessible: `kubectl get svc tempo -n observability`
- Check application is sending traces via OTLP

## Best Practices

1. **Service Names**: Use consistent naming: `{app-name}` for `OTEL_SERVICE_NAME`
2. **Resource Attributes**: Let applications set their own `service.name` (don't override in OTel Collector)
3. **Job Labels**: Use `job=otel-collector` for metrics to group all app metrics
4. **Log Collection**: For stdout/stderr logs, use Grafana Agent Operator (recommended)
5. **Namespace**: Use `observability` namespace for all observability components

## Example: Complete OTel Collector CR

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: observability
spec:
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      batch: {}
      resource:
        attributes:
          - key: job
            value: otel-collector
            action: upsert
    exporters:
      prometheusremotewrite:
        endpoint: http://prometheus-kube-prometheus-prometheus.observability.svc.cluster.local:9090/api/v1/write
      prometheus:
        endpoint: 0.0.0.0:8889
      otlphttp/loki:
        endpoint: http://loki-loki-distributed-gateway.observability.svc.cluster.local:80/otlp
      otlp/tempo:
        endpoint: tempo.observability.svc.cluster.local:4317
        tls:
          insecure: true
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [otlp/tempo]
        metrics:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [prometheusremotewrite, prometheus]
        logs:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [otlphttp/loki, debug]
  mode: deployment
  replicas: 1
  image: otel/opentelemetry-collector-contrib:latest
```

## References

- [OpenTelemetry Collector Documentation](https://opentelemetry.io/docs/collector/)
- [Loki OTLP Ingestion](https://grafana.com/docs/loki/latest/send-data/otel/)
- [Prometheus Remote Write](https://prometheus.io/docs/prometheus/latest/storage/#remote-storage-integrations)
- [Tempo Documentation](https://grafana.com/docs/tempo/latest/)
