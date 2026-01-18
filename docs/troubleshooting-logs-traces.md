# Troubleshooting Logs and Traces in Grafana

This guide helps you troubleshoot why logs and traces may not be appearing in Grafana.

## Architecture Overview

```
Application → OTel Collector → Loki 3.0+ (logs) / Tempo (traces) → Grafana
     │
     └→ stdout/stderr → FluentBit (Logging Operator) → Loki → Grafana
```

**Key services:**

- Loki gateway: `loki-gateway:80` (OTLP endpoint: `/otlp`)
- Tempo: `tempo:3200` (HTTP API) / `tempo:4317` (OTLP gRPC)
- Prometheus: `prometheus-kube-prometheus-prometheus:9090`

## Quick Diagnosis

Run the diagnostic script:

```bash
./scripts/debug-logs-traces.sh
```

## Common Issues

### Issue 1: Logs Not Appearing in Grafana

#### Symptoms

- Loki datasource is configured
- No logs visible in Grafana Explore
- OTel Collector is running

#### Causes and Solutions

**Cause 1: OTEL_LOGS_ENABLED not set**

- **Check**: `kubectl get deployment -n default dm-nkp-gitops-custom-app -o yaml | grep OTEL_LOGS_ENABLED`
- **Fix**: Add `OTEL_LOGS_ENABLED=true` to Helm values
- **Apply**: `kubectl rollout restart deployment/dm-nkp-gitops-custom-app -n default`

**Cause 2: Application not sending logs via OTLP**

- **Check**: Application logs should show "OTLP logging enabled"
- **Fix**: Ensure application code uses `telemetry.LogInfo()` or similar functions
- **Verify**: Check application logs: `kubectl logs -n default -l app=dm-nkp-gitops-custom-app --tail=20`

**Cause 3: OTel Collector not receiving logs**

- **Check**: `kubectl logs -n observability <otel-collector-pod> | grep -i "log\|error"`
- **Fix**: Verify OTel Collector logs pipeline is configured
- **Verify**: Check OTel Collector config: `kubectl get opentelemetrycollector -n observability otel-collector -o yaml`

**Cause 4: Loki endpoint incorrect**

- **Check**: OTel Collector exporter endpoint
- **Fix**: Verify Loki service name: `kubectl get svc -n observability | grep loki`
- **Update**: OTel Collector config should have: `endpoint: http://loki-gateway.observability.svc.cluster.local:80/otlp`
- **Note**: Loki 3.0+ is required for native OTLP log ingestion

**Cause 5: Not enough traffic**

- **Fix**: Generate more load: `./scripts/generate-load.sh`
- **Wait**: 30-60 seconds for logs to be processed

### Issue 2: Traces Not Appearing in Grafana

#### Symptoms

- Tempo datasource is configured
- No traces visible in Grafana Explore
- OTel Collector is running

#### Causes and Solutions

**Cause 1: Application not sending traces**

- **Check**: Application should use OpenTelemetry tracing
- **Verify**: Check if traces are being generated: `kubectl logs -n default -l app=dm-nkp-gitops-custom-app | grep -i trace`

**Cause 2: OTel Collector not forwarding traces**

- **Check**: OTel Collector traces pipeline configuration
- **Fix**: Verify exporter endpoint: `endpoint: tempo.observability.svc.cluster.local:4317`
- **Verify**: Check OTel Collector logs for errors

**Cause 3: Not enough traffic**

- **Fix**: Generate more load: `./scripts/generate-load.sh`
- **Wait**: 30-60 seconds for traces to be processed

### Issue 3: OTel Collector Errors

#### Symptoms

- OTel Collector pod has errors
- Logs show export failures

#### Common Errors

**Error: "remote write receiver needs to be enabled"**

- **Cause**: Prometheus remote write not enabled
- **Fix**: Enable remote write receiver in Prometheus (already handled in e2e-demo-otel.sh)

**Error: "connection refused"**

- **Cause**: Backend service (Loki/Tempo) not accessible
- **Fix**: Verify service names and ports: `kubectl get svc -n observability`

**Error: "404 Not Found"**

- **Cause**: Incorrect endpoint URL
- **Fix**: Verify endpoint URLs in OTel Collector config

## Step-by-Step Troubleshooting

### Step 1: Verify Application Configuration

```bash
# Check environment variables
kubectl get deployment -n default dm-nkp-gitops-custom-app -o yaml | grep OTEL

# Should see:
# - OTEL_EXPORTER_OTLP_ENDPOINT
# - OTEL_SERVICE_NAME
# - OTEL_LOGS_ENABLED=true  # Required for logs
```

### Step 2: Verify OTel Collector

```bash
# Check OTel Collector pod
kubectl get pods -n observability | grep collector

# Check OTel Collector configuration
kubectl get opentelemetrycollector -n observability otel-collector -o yaml

# Check OTel Collector logs
kubectl logs -n observability <otel-collector-pod> --tail=50
```

### Step 3: Verify Backend Services

```bash
# Check Loki
kubectl get svc -n observability | grep loki
kubectl get pods -n observability | grep loki

# Check Tempo
kubectl get svc -n observability | grep tempo
kubectl get pods -n observability | grep tempo
```

### Step 4: Generate Load and Verify

```bash
# Generate load
./scripts/generate-load.sh

# Wait for telemetry
sleep 30

# Verify
./scripts/verify-logs-traces.sh
```

### Step 5: Check Grafana Directly

```bash
# Port forward to Grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80

# Open http://localhost:3000
# - Go to Explore → Select Loki
# - Query OTLP logs: {service_name="dm-nkp-gitops-custom-app"}
# - Query FluentBit logs: {app_kubernetes_io_name="dm-nkp-gitops-custom-app"}
# - Go to Explore → Select Tempo
# - Query: { resource.service.name = "dm-nkp-gitops-custom-app" }
```

### Step 6: Verify Loki Labels

```bash
# Port forward to Loki
kubectl port-forward -n observability svc/loki-gateway 3100:80

# Check available labels
curl http://localhost:3100/loki/api/v1/labels | jq '.data'

# For OTLP logs, look for: service_name
# For FluentBit logs, look for: app_kubernetes_io_name, namespace
```

## Verification Checklist

- [ ] Application has `OTEL_LOGS_ENABLED=true` environment variable
- [ ] Application is sending logs via OTLP (check application logs)
- [ ] OTel Collector pod is running
- [ ] OTel Collector logs pipeline is configured
- [ ] OTel Collector has no errors in logs
- [ ] Loki service is accessible
- [ ] Tempo service is accessible
- [ ] Grafana datasources are configured
- [ ] Traffic has been generated
- [ ] Waited 30-60 seconds after generating traffic

## Scripts Available

1. **`./scripts/generate-load.sh`**
   - Generates load for testing
   - Configurable requests and endpoints

2. **`./scripts/debug-logs-traces.sh`**
   - Comprehensive debugging
   - Checks all components

3. **`./scripts/verify-logs-traces.sh`**
   - Verifies logs and traces in Grafana
   - Tests datasources

## Getting Help

If issues persist:

1. Run diagnostic script: `./scripts/debug-logs-traces.sh`
2. Check OTel Collector logs: `kubectl logs -n observability <otel-pod>`
3. Check application logs: `kubectl logs -n default -l app=dm-nkp-gitops-custom-app`
4. Verify configuration: `kubectl get opentelemetrycollector -n observability otel-collector -o yaml`
