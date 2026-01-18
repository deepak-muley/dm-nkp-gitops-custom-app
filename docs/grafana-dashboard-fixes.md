# Grafana Dashboard Data Issues - Fixed

## Issues Found and Fixed

### 1. ❌ Loki OTLP Endpoint Incorrect

**Problem**: OTel Collector was configured to send logs to `/otlp` endpoint, but Loki doesn't support OTLP endpoint format.

**Error in logs**:

```
error exporting items, request to http://loki-loki-distributed-gateway.observability.svc.cluster.local:80/otlp/v1/logs responded with HTTP Status Code 404
```

**Fix**: Changed endpoint from `/otlp` to `/loki/api/v1/push`:

```yaml
otlphttp/loki:
  endpoint: http://loki-loki-distributed-gateway.observability.svc.cluster.local:80/loki/api/v1/push
```

**Status**: ✅ Fixed in script and applied to cluster

### 2. ❌ Logs Dashboard Queries Too Narrow

**Problem**: Dashboard queries only looked for `service_name="dm-nkp-gitops-custom-app"` (OTLP logs), but didn't include `app_kubernetes_io_name="dm-nkp-gitops-custom-app"` (stdout/stderr logs from Logging Operator).

**Fix**: Updated all queries to include both labels:

```logql
{service_name="dm-nkp-gitops-custom-app"} or {app_kubernetes_io_name="dm-nkp-gitops-custom-app"}
```

**Status**: ✅ Fixed in dashboard JSON and ConfigMap

### 3. ✅ Prometheus Port Already Exists

**Status**: The OTel Collector service already has a `prometheus` port (8889), so ServiceMonitor should work.

### 4. ✅ Logging Operator Dashboard

**Status**: Dashboard `dashboard-loki-operator.json` exists and has been imported to Grafana (HTTP 200 response).

**Location**:

- Source: `grafana/dashboard-loki-operator.json`
- Chart: `chart/dm-nkp-gitops-custom-app/files/grafana/dashboard-loki-operator.json`
- Imported via script: `scripts/e2e-demo-otel.sh`

## Verification Steps

### Check OTel Collector Logs

```bash
kubectl logs -n observability -l app.kubernetes.io/managed-by=opentelemetry-operator --tail=20 | grep -i loki
```

Should see successful exports (no 404 errors).

### Check Loki for Logs

```bash
kubectl port-forward -n observability svc/loki-loki-distributed-gateway 3100:80

# Check for OTLP logs
curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={service_name="dm-nkp-gitops-custom-app"}' \
  --data-urlencode "start=$(date -u -v-15M +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000"

# Check for stdout/stderr logs
curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={app_kubernetes_io_name="dm-nkp-gitops-custom-app"}' \
  --data-urlencode "start=$(date -u -v-15M +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000"
```

### Check Grafana Dashboards

1. **Logs Dashboard**: `http://localhost:3000/d/dm-nkp-custom-app-logs/dm-nkp-gitops-custom-app-logs`
   - Should show logs with either `service_name` or `app_kubernetes_io_name` labels

2. **Logging Operator Dashboard**: Search for "Loki Logs (Logging Operator)" in Grafana
   - Shows logs collected by Logging Operator (stdout/stderr)

### Generate Test Traffic

```bash
# Generate HTTP requests to create logs
for i in {1..20}; do
  kubectl exec -n default -l app.kubernetes.io/name=dm-nkp-gitops-custom-app -- \
    curl -s http://localhost:8080/ > /dev/null 2>&1
done
```

Wait 30 seconds, then check dashboards again.

## Files Updated

1. ✅ `scripts/e2e-demo-otel.sh` - Fixed Loki endpoint
2. ✅ `chart/dm-nkp-gitops-custom-app/files/grafana/dashboard-logs.json` - Updated queries
3. ✅ `grafana/dashboard-loki-operator.json` - Logging Operator dashboard (already exists)
4. ✅ Cluster: OTel Collector CR patched with correct endpoint
5. ✅ Cluster: Logs dashboard ConfigMap updated

## Next Steps

1. Wait for OTel Collector to restart (already done)
2. Generate some application traffic to create logs
3. Wait 30-60 seconds for logs to propagate
4. Refresh Grafana dashboards
5. Check both dashboards:
   - `dm-nkp-gitops-custom-app - Logs` (OTLP + stdout/stderr)
   - `dm-nkp-gitops-custom-app - Loki Logs (Logging Operator)` (stdout/stderr only)

## Troubleshooting

If logs still don't appear:

1. **Check OTel Collector logs**:

   ```bash
   kubectl logs -n observability -l app.kubernetes.io/managed-by=opentelemetry-operator --tail=50 | grep -iE "(loki|error|export)"
   ```

2. **Check if application is sending logs**:

   ```bash
   kubectl logs -n default -l app.kubernetes.io/name=dm-nkp-gitops-custom-app --tail=10
   ```

3. **Check Loki labels**:

   ```bash
   kubectl port-forward -n observability svc/loki-loki-distributed-gateway 3100:80
   curl -s "http://localhost:3100/loki/api/v1/labels" | jq -r '.data[]'
   ```

4. **Check Logging Operator**:

   ```bash
   kubectl get pods -n logging
   kubectl get flow,output -n logging
   ```
