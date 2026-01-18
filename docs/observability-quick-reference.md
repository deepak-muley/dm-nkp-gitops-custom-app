# Observability Quick Reference

Quick reference guide for setting up observability for a new application.

## Application Configuration

### Environment Variables

```bash
OTEL_SERVICE_NAME=your-app-name
OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector-collector.observability.svc.cluster.local:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

### Send Telemetry

- **Metrics**: Via OTLP (automatic with OpenTelemetry SDK)
- **Traces**: Via OTLP (automatic with OpenTelemetry SDK)
- **Logs**:
  - Option 1: stdout/stderr (requires log collector)
  - Option 2: Via OTLP (recommended)

## OTel Collector Endpoints

### For Your Application

```
otel-collector-collector.observability.svc.cluster.local:4317 (gRPC)
otel-collector-collector.observability.svc.cluster.local:4318 (HTTP)
```

## Loki Configuration

### Endpoint (Compatible with Microservice/Distributed)

```yaml
# For Loki Distributed/Microservice (Platform)
endpoint: http://loki-loki-distributed-gateway.observability.svc.cluster.local:80/otlp

# For Loki Simple Scalable
endpoint: http://loki.observability.svc.cluster.local:3100/otlp
```

**✅ Both architectures use the same OTLP HTTP exporter configuration**

## Prometheus Configuration

### ServiceMonitor (Already Created)

- Name: `otel-collector`
- Namespace: `observability`
- Scrapes: `otel-collector-collector:8889/metrics`
- Job label: `otel-collector`

### Query Metrics

```promql
# All app metrics
{job="otel-collector"}

# Specific app
{job="otel-collector", service_name="your-app-name"}
```

## Grafana Queries

### Metrics (Prometheus)

```promql
sum(rate(http_requests_total{job="otel-collector"}[5m]))
```

### Logs (Loki)

```logql
{service_name="your-app-name"}
```

### Traces (Tempo)

```
service.name="your-app-name"
```

## Compatibility Checklist

- ✅ Works with Loki Simple Scalable
- ✅ Works with Loki Distributed/Microservice
- ✅ Works with platform-managed Loki
- ✅ No code changes needed when switching Loki architectures
- ✅ Use gateway service for distributed Loki

## Quick Setup Steps

1. **Set environment variables** in your application
2. **Initialize OpenTelemetry SDK** (metrics, traces, logs)
3. **Deploy application** - OTel Collector automatically receives telemetry
4. **Create Grafana dashboards** using the queries above

## Troubleshooting

| Issue | Solution |
|-------|----------|
| No metrics | Check `job="otel-collector"` label in queries |
| No logs | Deploy log collector OR send logs via OTLP |
| No traces | Verify `service.name` matches in Tempo queries |
| Wrong service name | Don't override `service.name` in OTel Collector resource processor |

## See Also

- Full documentation: [observability-setup.md](./observability-setup.md)
- Dashboard examples: [grafana/](../grafana/)
