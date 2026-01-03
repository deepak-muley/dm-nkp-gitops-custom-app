# Grafana Dashboard Guide

This guide explains how to use the Grafana dashboard to visualize Prometheus metrics from dm-nkp-gitops-custom-app.

## Dashboard Overview

The dashboard (`grafana/dashboard.json`) includes the following panels:

1. **HTTP Request Rate** - Shows the rate of HTTP requests over time
2. **Active HTTP Connections** - Gauge showing current active connections
3. **HTTP Request Duration (Percentiles)** - p50, p95, p99, and average request duration
4. **HTTP Response Size** - Distribution of response sizes (p50, p90, p99)
5. **HTTP Requests by Method and Status** - Breakdown of requests by HTTP method and status code
6. **Business Metrics** - Table showing custom business metrics
7. **Total Request Rate by Instance** - Request rate per application instance

## Importing Dashboard

### Option 1: Automatic Setup Script (Recommended)

For existing clusters, use the automated setup script:

```bash
# Basic usage (auto-detects Grafana and Prometheus)
./scripts/setup-grafana-dashboard.sh

# Specify custom namespace and service
./scripts/setup-grafana-dashboard.sh monitoring prometheus-grafana

# Specify Prometheus URL explicitly
./scripts/setup-grafana-dashboard.sh monitoring prometheus-grafana \
  http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090

# Use custom dashboard file
./scripts/setup-grafana-dashboard.sh monitoring prometheus-grafana "" \
  /path/to/custom-dashboard.json
```

This script will:
- ✅ Auto-detect Grafana service and namespace
- ✅ Configure Prometheus datasource automatically
- ✅ Import the dashboard
- ✅ Work with any existing cluster (not just kind)

### Option 2: Import from File

1. Open Grafana UI (usually http://localhost:3000)
2. Click on **"+"** → **"Import"**
3. Click **"Upload JSON file"**
4. Select `grafana/dashboard.json`
5. Click **"Load"**
6. Select Prometheus datasource
7. Click **"Import"**

### Option 3: Import via API

```bash
# Get Grafana password
GRAFANA_PASSWORD=$(kubectl get secret -n monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d)

# Port forward to Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &

# Import dashboard
curl -X POST \
  -u "admin:${GRAFANA_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d @grafana/dashboard.json \
  http://localhost:3000/api/dashboards/db
```

### Option 4: Automatic Provisioning (Kubernetes)

When deploying with the monitoring stack, the dashboard is automatically provisioned via ConfigMap.

## Using with E2E Tests

The e2e tests automatically set up:
- Application deployment
- Prometheus for metrics scraping
- Grafana with pre-configured dashboard

### Running E2E Tests

```bash
# Run e2e tests (will set up everything in kind cluster)
make e2e-tests

# Or manually:
go test -v -tags=e2e -timeout=30m ./tests/e2e/...
```

### Accessing Dashboard After E2E Tests

After e2e tests run, the kind cluster remains (by default) for inspection:

```bash
# Set kubectl context
kubectl config use-context kind-dm-nkp-test-cluster

# Port forward to Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Open browser
open http://localhost:3000
# Login: admin/admin
```

## Manual Setup in Kind Cluster

### 1. Create Kind Cluster

```bash
kind create cluster --name dm-nkp-test-cluster
```

### 2. Build and Load Application Image

```bash
# Build image
docker build -t dm-nkp-gitops-custom-app:test .

# Load into kind
kind load docker-image dm-nkp-gitops-custom-app:test --name dm-nkp-test-cluster
```

### 3. Deploy Application

```bash
# Update deployment to use local image
kubectl apply -f manifests/base/
kubectl set image deployment/dm-nkp-gitops-custom-app app=dm-nkp-gitops-custom-app:test
```

### 4. Deploy Monitoring Stack

```bash
# Use the Helm-based setup script (recommended)
./scripts/setup-monitoring-helm.sh dm-nkp-test-cluster default

# Or use the Makefile target:
make setup-monitoring-helm

# Or manually with Helm:
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort=30090
```

### 5. Generate Traffic

```bash
# Port forward to application
kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080

# In another terminal, generate traffic
for i in {1..100}; do
  curl http://localhost:8080/
  sleep 0.1
done
```

### 6. Access Grafana

```bash
# Port forward to Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Open browser
open http://localhost:3000
# Login: admin/admin
```

## Dashboard Panels Explained

### HTTP Request Rate
- **Query**: `rate(http_requests_total[5m])`
- **Shows**: Requests per second over time
- **Use**: Monitor application load

### Active HTTP Connections
- **Query**: `http_active_connections`
- **Shows**: Current number of active connections
- **Use**: Monitor connection pool usage

### HTTP Request Duration
- **Queries**: 
  - p50: `histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))`
  - p95: `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))`
  - p99: `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))`
- **Shows**: Request latency percentiles
- **Use**: Monitor application performance

### HTTP Response Size
- **Queries**: `http_response_size_bytes{quantile="0.5|0.9|0.99"}`
- **Shows**: Response size distribution
- **Use**: Monitor response payload sizes

### HTTP Requests by Method and Status
- **Query**: `rate(http_requests_by_method_total[5m])`
- **Shows**: Request breakdown by HTTP method and status code
- **Use**: Monitor API usage patterns and error rates

### Business Metrics
- **Query**: `business_metric_value`
- **Shows**: Custom business metrics in table format
- **Use**: Display custom application metrics

## Customizing the Dashboard

### Adding New Panels

1. Open Grafana UI
2. Edit the dashboard
3. Click **"Add panel"**
4. Configure query and visualization
5. Save dashboard
6. Export JSON and update `grafana/dashboard.json`

### Modifying Queries

All queries use Prometheus PromQL. Common modifications:

```promql
# Change time range
rate(http_requests_total[1m])  # 1 minute instead of 5

# Add filters
rate(http_requests_total{method="GET"}[5m])

# Aggregate
sum(rate(http_requests_total[5m])) by (instance)
```

## Troubleshooting

### Dashboard Shows "No Data"

1. **Check Prometheus is scraping**:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   # Open http://localhost:9090/targets
   # Verify dm-nkp-gitops-custom-app target is UP
   ```

2. **Check metrics are being generated**:
   ```bash
   kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 9090:9090
   curl http://localhost:9090/metrics
   ```

3. **Generate traffic**:
   ```bash
   for i in {1..50}; do curl http://localhost:8080/; done
   ```

### Grafana Can't Connect to Prometheus

1. Check Prometheus service:
   ```bash
   kubectl get svc -n monitoring prometheus
   ```

2. Check Grafana datasource configuration:
   ```bash
   kubectl get configmap -n monitoring grafana-datasources -o yaml
   ```

3. Verify Prometheus is accessible from Grafana pod:
   ```bash
   kubectl exec -n monitoring deployment/grafana -- wget -qO- http://prometheus:9090/api/v1/status/config
   ```

### Dashboard Not Appearing

1. Check dashboard ConfigMap:
   ```bash
   kubectl get configmap -n monitoring grafana-dashboard
   ```

2. Check Grafana logs:
   ```bash
   kubectl logs -n monitoring deployment/grafana
   ```

3. Manually import dashboard (see Importing Dashboard section)

## Prometheus Queries Reference

Useful Prometheus queries for ad-hoc exploration:

```promql
# Total requests
sum(http_requests_total)

# Request rate
rate(http_requests_total[5m])

# Average request duration
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])

# 95th percentile duration
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Requests by status
sum(rate(http_requests_by_method_total[5m])) by (status)

# Active connections
http_active_connections

# Business metrics
business_metric_value
```

## Resources

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Prometheus Query Language](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Dashboard JSON Format](https://grafana.com/docs/grafana/latest/dashboards/json-dashboard/)

