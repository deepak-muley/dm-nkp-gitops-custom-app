# Grafana Dashboard Verification Checklist

After running `scripts/e2e-demo-otel.sh`, use this checklist to verify that all dashboards are showing data correctly.

## Prerequisites

1. Script has completed successfully
2. Kind cluster is running: `kind get clusters | grep dm-nkp-demo-cluster`
3. Kubectl context is set: `kubectl config use-context kind-dm-nkp-demo-cluster`

## Step 1: Port Forward to Grafana

```bash
kubectl port-forward -n observability svc/prometheus-grafana 3000:80
```

Keep this running in a separate terminal.

## Step 2: Access Grafana UI

1. Open browser: <http://localhost:3000>
2. Login credentials:
   - Username: `admin`
   - Password: Get with:

     ```bash
     kubectl get secret -n observability prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d
     ```

## Step 3: Verify Data Sources

In Grafana UI:

1. Navigate to **Configuration** → **Data sources**
2. Verify all three datasources exist and are working:

   ✅ **Prometheus**
   - URL: `http://prometheus-kube-prometheus-prometheus.observability.svc.cluster.local:9090`
   - Status: Should show green "Data source is working"
   - Test query: Click "Save & Test" - should succeed

   ✅ **Loki**
   - URL: Should be `http://loki-loki-distributed-gateway.observability.svc.cluster.local:80` or detected service
   - Status: Should show green "Data source is working"
   - Test query: Click "Save & Test" - should succeed

   ✅ **Tempo**
   - URL: Should be `http://tempo.observability.svc.cluster.local:3200` or detected service
   - Status: Should show green "Data source is working"
   - Test query: Click "Save & Test" - should succeed

If any datasource is missing or not working:

```bash
# Check ConfigMap
kubectl get configmap -n observability -l grafana_datasource=1

# Check Grafana logs
kubectl logs -n observability -l app.kubernetes.io/name=grafana --tail=50 | grep -i datasource
```

## Step 4: Verify Dashboards Are Discovered

1. In Grafana UI, go to **Dashboards** → **Browse**
2. Check that dashboards appear:
   - `dm-nkp-gitops-custom-app Metrics` (or similar name)
   - `dm-nkp-gitops-custom-app Logs`
   - `dm-nkp-gitops-custom-app Traces`

Alternatively, verify via kubectl:

```bash
# Check dashboard ConfigMaps
kubectl get configmap -n observability -l grafana_dashboard=1

# Should show multiple ConfigMaps with names like:
# - dm-nkp-gitops-custom-app-grafana-dashboard-metrics
# - dm-nkp-gitops-custom-app-grafana-dashboard-logs
# - dm-nkp-gitops-custom-app-grafana-dashboard-traces
```

## Step 5: Verify Metrics Dashboard Shows Data

1. Open the **Metrics** dashboard in Grafana
2. Check each panel:

   ✅ **HTTP Request Rate**
   - Panel should show a line graph (not "No data")
   - Should have data points over the last 5-15 minutes
   - Query: `sum(rate(http_server_duration_milliseconds_count{job="otel-collector",exported_job="dm-nkp-gitops-custom-app"}[5m]))`

   ✅ **Active HTTP Connections**
   - Should show a gauge with a value > 0
   - Query: `http_active_connections{job="otel-collector",exported_job="dm-nkp-gitops-custom-app"}`

   ✅ **HTTP Request Duration (Percentiles)**
   - Should show lines for p50, p95, p99
   - Query pattern: `histogram_quantile(...)`

   ✅ **HTTP Response Size**
   - Should show percentiles (p50, p90, p99)
   - Query pattern: `histogram_quantile(...)`

   ✅ **HTTP Requests by Method and Status**
   - Should show bars or lines for different HTTP methods/status codes
   - Query: `rate(http_requests_by_method_total[5m])`

   ✅ **Business Metrics Table**
   - Should show a table with business metrics (may be empty if no business metrics are emitted)

   ✅ **Total Request Rate by Instance**
   - Should show request rates per instance/pod
   - Query: `sum(rate(http_requests_total[5m])) by (instance)`

### Troubleshooting Metrics Dashboard

If panels show "No data":

1. **Check Prometheus is scraping OTel Collector:**

   ```bash
   kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
   # Open http://localhost:9090/targets
   # Look for "otel-collector" target - should be UP
   ```

2. **Check metrics in Prometheus directly:**

   ```bash
   # In Prometheus UI (http://localhost:9090), try queries:
   otelcol_receiver_accepted_metrics
   http_server_duration_milliseconds_count
   ```

3. **Verify application is sending metrics:**

   ```bash
   # Check app pods are running
   kubectl get pods -n default -l app.kubernetes.io/name=dm-nkp-gitops-custom-app
   
   # Check OTel Collector is receiving data
   kubectl logs -n observability -l app.kubernetes.io/managed-by=opentelemetry-operator --tail=50 | grep -i metric
   ```

4. **Generate more traffic:**

   ```bash
   kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080
   # In another terminal:
   for i in {1..100}; do curl http://localhost:8080/; sleep 0.1; done
   ```

## Step 6: Verify Logs Dashboard Shows Data

1. Open the **Logs** dashboard in Grafana
2. Check panels:

   ✅ **Application Logs**
   - Should show log lines from the application
   - Query: `{service_name="dm-nkp-gitops-custom-app"}` or `{app_kubernetes_io_name="dm-nkp-gitops-custom-app"}`
   - Log entries should appear in the panel

   ✅ **Log Volume Over Time**
   - Should show a time series of log volume
   - Query: `sum(count_over_time({service_name="dm-nkp-gitops-custom-app"}[1m]))`

### Troubleshooting Logs Dashboard

If panels show "No data":

1. **Check Loki is receiving logs:**

   ```bash
   kubectl port-forward -n observability svc/loki-loki-distributed-gateway 3100:80
   # Query Loki API:
   curl "http://localhost:3100/loki/api/v1/labels"
   ```

2. **Check application logs:**

   ```bash
   kubectl logs -n default -l app.kubernetes.io/name=dm-nkp-gitops-custom-app --tail=50
   ```

3. **Check Logging Operator (for stdout/stderr logs):**

   ```bash
   kubectl get pods -n logging
   kubectl get logging,output,flow -n logging
   ```

4. **Check OTel Collector logs pipeline:**

   ```bash
   kubectl logs -n observability -l app.kubernetes.io/managed-by=opentelemetry-operator --tail=50 | grep -i log
   ```

## Step 7: Verify Traces Dashboard Shows Data

1. Open the **Traces** dashboard in Grafana
2. Check panels:

   ✅ **Trace Search**
   - Should show a search interface to find traces
   - Should list available traces with trace IDs

   ✅ **Trace Timeline**
   - Should show spans over time
   - Query: Uses Tempo datasource (not PromQL)

### Troubleshooting Traces Dashboard

If panels show "No data":

1. **Check Tempo is receiving traces:**

   ```bash
   kubectl port-forward -n observability svc/tempo 3200:3200
   # Query Tempo API:
   curl "http://localhost:3200/api/search?limit=10"
   ```

2. **Verify OTel Collector traces pipeline:**

   ```bash
   kubectl logs -n observability -l app.kubernetes.io/managed-by=opentelemetry-operator --tail=50 | grep -i trace
   ```

3. **Generate more traffic (traces are created per request):**

   ```bash
   kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080
   for i in {1..50}; do curl http://localhost:8080/; sleep 0.2; done
   # Wait 30 seconds, then check Tempo again
   ```

## Step 8: Quick Health Check Script

Run this script to quickly check all components:

```bash
#!/bin/bash
OBSERVABILITY_NAMESPACE="observability"
APP_NAMESPACE="default"

echo "=== Checking Data Sources ConfigMap ==="
kubectl get configmap -n $OBSERVABILITY_NAMESPACE -l grafana_datasource=1

echo -e "\n=== Checking Dashboard ConfigMaps ==="
kubectl get configmap -n $OBSERVABILITY_NAMESPACE -l grafana_dashboard=1

echo -e "\n=== Checking Prometheus Targets ==="
kubectl port-forward -n $OBSERVABILITY_NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090 &
PF_PID=$!
sleep 3
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | contains("otel")) | {job: .labels.job, health: .health, lastScrape: .lastScrape}'
kill $PF_PID 2>/dev/null || true

echo -e "\n=== Checking Application Pods ==="
kubectl get pods -n $APP_NAMESPACE -l app.kubernetes.io/name=dm-nkp-gitops-custom-app

echo -e "\n=== Checking OTel Collector ==="
kubectl get pods -n $OBSERVABILITY_NAMESPACE -l app.kubernetes.io/managed-by=opentelemetry-operator
```

## Common Issues and Solutions

### Issue: Datasources not appearing in Grafana

**Solution:**

- Check if ConfigMap exists: `kubectl get configmap -n observability -l grafana_datasource=1`
- Check Grafana is configured to auto-discover datasources (kube-prometheus-stack should do this by default)
- Restart Grafana pod to force re-read: `kubectl delete pod -n observability -l app.kubernetes.io/name=grafana`

### Issue: Dashboards show "No data" even though datasources are configured

**Possible causes:**

1. **Time range too narrow** - Try selecting "Last 15 minutes" or "Last 1 hour" in Grafana
2. **No metrics/logs/traces generated yet** - Generate traffic (see troubleshooting sections above)
3. **Query labels don't match** - Check actual metric/log label names in Prometheus/Loki:

   ```bash
   # Check Prometheus metrics
   kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
   # Visit http://localhost:9090 and search for metrics starting with "http_"
   ```

### Issue: "Data source is working" but queries return no data

**Solution:**

- Verify metrics/logs/traces exist in the backend (Prometheus/Loki/Tempo)
- Check query syntax matches actual metric/log names
- Verify time range includes the period when data was generated
- Check labels in queries match actual labels in data

## Expected Results After Script Completion

After `scripts/e2e-demo-otel.sh` completes successfully:

- ✅ All 3 datasources (Prometheus, Loki, Tempo) should be configured and working
- ✅ At least 3-5 dashboards should be discovered and visible
- ✅ Metrics dashboard should show data after traffic generation (Step 10 of script)
- ✅ Logs dashboard should show application logs
- ✅ Traces dashboard should show traces from generated traffic

The script generates 100 requests in Step 10, which should create enough data to verify dashboards are working.

## Next Steps

If all dashboards are showing data correctly:

- ✅ Configuration is working as expected!
- The datasource and dashboard ConfigMaps are properly deployed
- Grafana is discovering and using them correctly

If issues persist:

- Check the troubleshooting sections above
- Review Grafana logs: `kubectl logs -n observability -l app.kubernetes.io/name=grafana`
- Verify Helm values were applied correctly: `helm get values dm-nkp-gitops-custom-app -n default`
