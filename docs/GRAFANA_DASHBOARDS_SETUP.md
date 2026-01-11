# Grafana Dashboards Setup Guide

## Overview

This guide explains how Grafana dashboards are deployed and configured for the application, both for local testing and production deployments.

## Architecture

### Local Testing (Development)

```
chart/observability-stack (LOCAL TESTING ONLY)
  └─ Deploys: OTel Collector, Prometheus, Loki, Tempo, Grafana

chart/dm-nkp-gitops-custom-app
  └─ Deploys: App + App-specific CRs (ServiceMonitor, Grafana Dashboards)
```

### Production (K8s Cluster)

```
Platform Services (Pre-deployed by platform team)
  └─ OTel Collector, Prometheus, Loki, Tempo, Grafana

chart/dm-nkp-gitops-custom-app (Application Chart)
  └─ Deploys: App + App-specific CRs (ServiceMonitor, Grafana Dashboards)
      - References pre-deployed platform services
      - Configures ServiceMonitor to scrape OTel Collector
      - Deploys Grafana Dashboard ConfigMaps
```

## Grafana Dashboards

### Available Dashboards

1. **Metrics Dashboard** (`dashboard-metrics.json`)
   - Data Source: Prometheus
   - Panels:
     - HTTP Request Rate
     - Active HTTP Connections (Gauge)
     - Request Duration Percentiles (p50, p95, p99, avg)
     - HTTP Response Size Distribution
     - HTTP Requests by Method and Status
     - Business Metrics Table

2. **Logs Dashboard** (`dashboard-logs.json`)
   - Data Source: Loki
   - Panels:
     - Application Logs Stream
     - Log Volume (logs per minute)
     - Log Levels Breakdown (INFO, WARN, ERROR)
     - Error Logs Stream

3. **Traces Dashboard** (`dashboard-traces.json`)
   - Data Source: Tempo
   - Panels:
     - Trace Search (by service name)
     - Trace Rate (traces per second)
     - Trace Duration Distribution
     - Traces by HTTP Route
     - Traces by HTTP Status Code

## Deployment

### Local Testing Setup

1. **Deploy Observability Stack** (local testing only):
   ```bash
   helm upgrade --install observability-stack ./chart/observability-stack \
     --namespace observability \
     --create-namespace \
     --wait
   ```

2. **Deploy Application with Dashboards**:
   ```bash
   helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
     --namespace default \
     --set opentelemetry.enabled=true \
     --set grafana.dashboards.enabled=true \
     --set grafana.dashboards.namespace=observability
   ```

3. **Configure Grafana Dashboard Discovery**:
   
   Grafana needs to discover dashboards from ConfigMaps. If using kube-prometheus-stack, it usually auto-discovers. Otherwise, configure dashboard provider:

   ```yaml
   # grafana-dashboard-provider.yaml
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

   And update Grafana deployment to mount ConfigMaps:

   ```yaml
   volumeMounts:
     - name: app-dashboards
       mountPath: /var/lib/grafana/dashboards
   volumes:
     - name: app-dashboards
       configMap:
         name: grafana-dashboard-provider
   ```

### Production Deployment

In production, platform services are pre-deployed. Only deploy the application chart:

```bash
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  --set opentelemetry.enabled=true \
  --set opentelemetry.collector.endpoint=otel-collector.observability.svc.cluster.local:4317 \
  --set grafana.dashboards.enabled=true \
  --set grafana.dashboards.namespace=observability \
  --set monitoring.serviceMonitor.enabled=true \
  --set monitoring.serviceMonitor.namespace=observability \
  --set monitoring.serviceMonitor.otelCollector.namespace=observability \
  --set monitoring.serviceMonitor.otelCollector.selectorLabels.app.kubernetes.io/name=opentelemetry-collector
```

## Configuration

### Application Chart Values

```yaml
# Grafana Dashboard Configuration
grafana:
  dashboards:
    enabled: true
    namespace: "observability"  # Namespace where Grafana is deployed
    folder: "/"  # Grafana folder for dashboards

# Monitoring Configuration
monitoring:
  serviceMonitor:
    enabled: true
    namespace: "observability"  # Namespace where Prometheus Operator is deployed
    interval: 30s
    scrapeTimeout: 10s
    otelCollector:
      namespace: "observability"  # Platform namespace
      selectorLabels:
        component: otel-collector
        # Or use platform-specific labels:
        # app.kubernetes.io/name: opentelemetry-collector
      prometheusPort: "prometheus"
      prometheusPath: "/metrics"
```

### Platform Service References

The application chart references pre-deployed platform services via configurable values:

```yaml
opentelemetry:
  collector:
    endpoint: "otel-collector.observability.svc.cluster.local:4317"  # Adjust for your platform
```

## Dashboard Discovery

Grafana discovers dashboards via ConfigMaps with:
- Label: `grafana_dashboard=1`
- Annotation: `grafana-folder: "/"` (optional)

The application chart automatically applies these labels/annotations.

## Manual Dashboard Import

If automatic discovery doesn't work, you can manually import dashboards:

1. Port-forward to Grafana:
   ```bash
   kubectl port-forward -n observability svc/prometheus-grafana 3000:80
   ```

2. Access Grafana: `http://localhost:3000`

3. Import dashboard:
   - Go to Dashboards → Import
   - Upload `grafana/dashboard-metrics.json` (or logs/traces)
   - Select appropriate data source (Prometheus/Loki/Tempo)
   - Import

## Troubleshooting

### Dashboards Not Appearing in Grafana

1. **Check ConfigMaps are created**:
   ```bash
   kubectl get configmap -n observability -l grafana_dashboard=1
   ```

2. **Check Grafana dashboard discovery is configured**:
   ```bash
   kubectl get configmap -n observability grafana-dashboard-provider -o yaml
   ```

3. **Check Grafana logs**:
   ```bash
   kubectl logs -n observability deployment/prometheus-grafana | grep -i dashboard
   ```

4. **Verify dashboard JSON is valid**:
   ```bash
   # Validate JSON syntax
   jq . grafana/dashboard-metrics.json > /dev/null
   ```

### Dashboard Shows "No Data"

1. **Metrics Dashboard**:
   - Verify Prometheus is scraping OTel Collector
   - Check Prometheus targets: `kubectl port-forward -n observability svc/prometheus 9090:9090` → `http://localhost:9090/targets`
   - Verify application is generating metrics
   - Check metric names match queries in dashboard

2. **Logs Dashboard**:
   - Verify Loki is receiving logs from OTel Collector
   - Check application logs: `kubectl logs -n default deployment/dm-nkp-gitops-custom-app`
   - Verify log labels match Loki queries: `{service_name="dm-nkp-gitops-custom-app"}`

3. **Traces Dashboard**:
   - Verify Tempo is receiving traces from OTel Collector
   - Check OTel Collector logs: `kubectl logs -n observability deployment/otel-collector`
   - Verify service name in traces: `service.name=dm-nkp-gitops-custom-app`

### ServiceMonitor Not Working

1. **Check ServiceMonitor is created**:
   ```bash
   kubectl get servicemonitor -n observability -l app=dm-nkp-gitops-custom-app
   ```

2. **Verify Prometheus Operator is installed**:
   ```bash
   kubectl get crd servicemonitors.monitoring.coreos.com
   ```

3. **Check Prometheus is discovering ServiceMonitor**:
   - Port-forward to Prometheus
   - Go to Status → Service Discovery
   - Look for your ServiceMonitor

4. **Verify OTel Collector service matches selector**:
   ```bash
   kubectl get svc -n observability -l component=otel-collector
   ```

## Customization

### Adding Custom Panels

1. Edit dashboard JSON files in `grafana/` directory
2. Re-deploy application chart to update ConfigMaps
3. Refresh Grafana to see changes

### Changing Data Sources

Update dashboard JSON files to reference different data sources:
- Prometheus: `"datasource": "Prometheus"`
- Loki: `"datasource": "Loki"`
- Tempo: `"datasource": {"type": "tempo", "uid": "tempo"}`

Ensure data source names/UIDs match your Grafana configuration.

## Summary

- **Local Testing**: Deploy `observability-stack` chart first, then application chart
- **Production**: Only deploy application chart (references pre-deployed platform services)
- **Dashboards**: Automatically deployed as ConfigMaps with proper labels
- **ServiceMonitor**: Configures Prometheus to scrape OTel Collector's metrics endpoint
- **Configuration**: Adjustable via Helm values for different platform setups
