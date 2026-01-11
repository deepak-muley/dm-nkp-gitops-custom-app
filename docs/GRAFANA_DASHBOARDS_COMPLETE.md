# Grafana Dashboards - Complete Setup Summary

## Overview

Grafana dashboards for metrics, logs, and traces are now fully configured and ready for deployment. All dashboards are deployed via the application Helm chart as ConfigMaps.

## Dashboards Created

### 1. Metrics Dashboard (`dashboard-metrics.json`)

**Data Source**: Prometheus

**Panels**:
- ✅ HTTP Request Rate (timeseries)
- ✅ Active HTTP Connections (gauge)
- ✅ HTTP Request Duration Percentiles (p50, p95, p99, avg)
- ✅ HTTP Response Size Distribution (p50, p90, p99)
- ✅ HTTP Requests by Method and Status (timeseries)
- ✅ Business Metrics (table)

**Location**: `grafana/dashboard-metrics.json` and `chart/dm-nkp-gitops-custom-app/files/grafana/dashboard-metrics.json`

### 2. Logs Dashboard (`dashboard-logs.json`)

**Data Source**: Loki

**Panels**:
- ✅ Application Logs Stream (logs panel)
- ✅ Log Volume (timeseries)
- ✅ Log Levels Breakdown (INFO/WARN/ERROR)
- ✅ Error Logs Stream (filtered logs)

**Location**: `grafana/dashboard-logs.json` and `chart/dm-nkp-gitops-custom-app/files/grafana/dashboard-logs.json`

### 3. Traces Dashboard (`dashboard-traces.json`)

**Data Source**: Tempo

**Panels**:
- ✅ Trace Search (traces panel)
- ✅ Trace Rate (timeseries)
- ✅ Trace Duration Distribution (histogram)
- ✅ Traces by HTTP Route (timeseries)
- ✅ Traces by HTTP Status Code (timeseries)

**Location**: `grafana/dashboard-traces.json` and `chart/dm-nkp-gitops-custom-app/files/grafana/dashboard-traces.json`

## Deployment

### Local Testing

```bash
# 1. Deploy observability stack (LOCAL TESTING ONLY)
helm install observability-stack ./chart/observability-stack \
  --namespace observability --create-namespace

# 2. Deploy application with dashboards
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  -f ./chart/dm-nkp-gitops-custom-app/values-local-testing.yaml
```

### Production

```bash
# Only deploy application chart (platform services pre-deployed)
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  -f ./chart/dm-nkp-gitops-custom-app/values-production.yaml \
  --set grafana.dashboards.namespace=observability
```

## Verification

### Check Dashboards are Deployed

```bash
kubectl get configmap -n observability -l grafana_dashboard=1
```

Expected output:
```
NAME                                          DATA   AGE
dm-nkp-gitops-custom-app-grafana-dashboard-metrics   1    1m
dm-nkp-gitops-custom-app-grafana-dashboard-logs      1    1m
dm-nkp-gitops-custom-app-grafana-dashboard-traces    1    1m
```

### Access Dashboards in Grafana

```bash
# Port-forward to Grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80

# Access: http://localhost:3000
# Login: admin/admin

# Navigate to: Dashboards → Browse
# Should see all three dashboards
```

## Configuration

### Enable/Disable Dashboards

```yaml
grafana:
  dashboards:
    enabled: true  # Set to false to disable
    namespace: "observability"  # Where Grafana is deployed
    folder: "/"  # Grafana folder
```

### Configure Namespace

For production, set the Grafana namespace:

```yaml
grafana:
  dashboards:
    namespace: "observability"  # Your platform's Grafana namespace
```

## Dashboard Discovery

Grafana needs to be configured to discover dashboards from ConfigMaps with label `grafana_dashboard=1`.

### For kube-prometheus-stack

The `kube-prometheus-stack` chart usually auto-configures dashboard discovery. Dashboards with label `grafana_dashboard=1` are automatically discovered.

### Manual Configuration (if needed)

Create a Grafana dashboard provider ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-provider
  namespace: observability
data:
  dashboards.yaml: |
    apiVersion: 1
    providers:
    - name: 'App Dashboards'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      editable: true
      allowUiUpdates: true
      options:
        path: /var/lib/grafana/dashboards
```

And mount ConfigMaps in Grafana deployment (usually handled by kube-prometheus-stack).

## Troubleshooting

### Dashboards Not Appearing

1. **Check ConfigMaps exist**:
   ```bash
   kubectl get configmap -n observability -l grafana_dashboard=1
   ```

2. **Verify Grafana dashboard discovery**:
   ```bash
   kubectl get configmap -n observability -l grafana_dashboard_provider=1
   ```

3. **Check Grafana logs**:
   ```bash
   kubectl logs -n observability deployment/prometheus-grafana | grep -i dashboard
   ```

4. **Manual import** (if needed):
   - Port-forward to Grafana
   - Go to Dashboards → Import
   - Upload JSON files from `grafana/` directory

### Dashboard Shows "No Data"

1. **Metrics Dashboard**:
   - Verify Prometheus is scraping OTel Collector
   - Check application is generating metrics
   - Verify metric names match queries

2. **Logs Dashboard**:
   - Check application logs: `kubectl logs deployment/dm-nkp-gitops-custom-app`
   - Verify OTel Collector is forwarding to Loki
   - Check Loki query syntax

3. **Traces Dashboard**:
   - Verify application is creating traces
   - Check OTel Collector is forwarding to Tempo
   - Verify service name in Tempo queries

## Summary

✅ **Three complete dashboards** ready for metrics, logs, and traces
✅ **Automatic deployment** via Helm chart as ConfigMaps
✅ **Proper labels** for Grafana discovery
✅ **Separated for production** - app chart deploys only app-specific CRs
✅ **Local testing** - observability-stack chart for complete stack
✅ **Production ready** - references pre-deployed platform services

All dashboards are validated and ready to use!
