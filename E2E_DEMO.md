# End-to-End Demo Guide

This guide walks you through running the complete end-to-end demo, including viewing metrics in the Grafana dashboard.

## Quick Start

Run the automated script:
```bash
./scripts/run-e2e-demo.sh
```

Then follow the instructions at the end to access Grafana.

## Manual Step-by-Step

### Prerequisites

Ensure you have:
- Go 1.25+
- Docker running
- kubectl installed
- kind installed
- helm installed (optional)

### Step 1: Build Application

```bash
# Clean and prepare
make clean
make deps

# Build
make build

# Verify binary
ls -lh bin/dm-nkp-gitops-custom-app
```

### Step 2: Run Tests

```bash
# Unit tests
make unit-tests

# Integration tests (optional)
make integration-tests
```

### Step 3: Build Docker Image

```bash
# Build image
docker build -t dm-nkp-gitops-custom-app:demo .

# Verify image
docker images | grep dm-nkp-gitops-custom-app
```

### Step 4: Create Kind Cluster

```bash
# Create cluster
kind create cluster --name dm-nkp-demo-cluster

# Verify
kubectl cluster-info --context kind-dm-nkp-demo-cluster
```

### Step 5: Load Image into Kind

```bash
# Load Docker image into kind
kind load docker-image dm-nkp-gitops-custom-app:demo --name dm-nkp-demo-cluster

# Verify
docker exec dm-nkp-demo-cluster-control-plane crictl images | grep dm-nkp
```

### Step 6: Deploy Application

```bash
# Create namespace
kubectl create namespace default

# Update deployment to use demo image
cat manifests/base/deployment.yaml | \
    sed 's|image:.*|image: dm-nkp-gitops-custom-app:demo|' | \
    sed 's|imagePullPolicy:.*|imagePullPolicy: Never|' | \
    kubectl apply -f -

# Deploy service
kubectl apply -f manifests/base/service.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app=dm-nkp-gitops-custom-app --timeout=2m

# Verify
kubectl get pods -l app=dm-nkp-gitops-custom-app
kubectl get svc dm-nkp-gitops-custom-app
```

### Step 7: Deploy Monitoring Stack (Using Helm)

```bash
# Option 1: Use automated script (Recommended)
make setup-monitoring-helm

# Option 2: Manual Helm installation
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Prometheus Operator (includes Prometheus)
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort=30090 \
  --wait --timeout=5m

# Install Grafana
helm upgrade --install grafana grafana/grafana \
  --namespace monitoring \
  --set adminPassword=admin \
  --set service.type=NodePort \
  --set service.nodePort=30300 \
  --set persistence.enabled=false \
  --wait --timeout=5m

# Verify
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

**Note**: Monitoring is now deployed using Helm charts (kube-prometheus-stack). The old YAML manifests have been removed in favor of Helm-based deployment.

### Step 8: Generate Traffic

Generate traffic to create metrics:

```bash
# Port forward to application (in background)
kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080 &
PF_PID=$!

# Wait a moment
sleep 2

# Generate traffic
for i in {1..100}; do
    curl -s http://localhost:8080/ >/dev/null
    curl -s http://localhost:8080/health >/dev/null
    sleep 0.1
done

# Stop port forward
kill $PF_PID

# Wait for metrics to be scraped
echo "Waiting for Prometheus to scrape metrics..."
sleep 10
```

### Step 9: Access Grafana Dashboard

#### Option A: Port Forward (Recommended)

```bash
# Port forward to Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

Then:
1. Open browser: http://localhost:3000
2. Login:
   - Username: `admin`
   - Password: `admin`
3. Navigate to dashboard:
   - Click "Dashboards" in left menu
   - Find "dm-nkp-gitops-custom-app Metrics"
   - Click to open

#### Option B: NodePort (if kind supports it)

```bash
# Get node IP
kubectl get nodes -o wide

# Access via NodePort 30300
# http://<node-ip>:30300
```

### Step 10: View Metrics in Grafana

Once in the dashboard, you should see:

1. **HTTP Request Rate** - Shows requests per second
2. **Active HTTP Connections** - Current active connections
3. **HTTP Request Duration** - p50, p95, p99 latencies
4. **HTTP Response Size** - Response size distribution
5. **HTTP Requests by Method and Status** - Breakdown by method/status
6. **Business Metrics** - Custom business metrics table

### Step 11: Verify Prometheus

```bash
# Port forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

Then:
1. Open browser: http://localhost:9090
2. Go to "Status" → "Targets"
3. Verify `dm-nkp-gitops-custom-app` target is UP
4. Try queries:
   - `http_requests_total`
   - `rate(http_requests_total[5m])`
   - `http_active_connections`
   - `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))`

### Step 12: Generate More Traffic

To see metrics update in real-time:

```bash
# Port forward
kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080 &

# Generate continuous traffic
while true; do
    for i in {1..20}; do
        curl -s http://localhost:8080/ >/dev/null
    done
    sleep 2
done
```

Watch the Grafana dashboard update in real-time!

## Troubleshooting

### Application Not Starting

```bash
# Check pods
kubectl get pods -l app=dm-nkp-gitops-custom-app

# Check logs
kubectl logs -l app=dm-nkp-gitops-custom-app

# Check events
kubectl describe pod -l app=dm-nkp-gitops-custom-app
```

### Prometheus Not Scraping

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/targets

# Check service endpoints
kubectl get endpoints dm-nkp-gitops-custom-app

# Check ServiceMonitor (if using)
kubectl get servicemonitor
```

### Grafana Dashboard Empty

1. **Check Prometheus datasource**:
   - Grafana → Configuration → Data Sources
   - Verify Prometheus is configured and working

2. **Check metrics exist**:
   ```bash
   kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 9090:9090
   curl http://localhost:9090/metrics | grep http_requests_total
   ```

3. **Generate more traffic**:
   ```bash
   for i in {1..200}; do curl http://localhost:8080/; done
   ```

4. **Check time range** in Grafana (should be "Last 15 minutes")

### Dashboard Not Appearing

```bash
# Check dashboard ConfigMap
kubectl get configmap -n monitoring grafana-dashboard

# Check Grafana logs
kubectl logs -n monitoring -l app=grafana

# Manually import dashboard
# In Grafana: + → Import → Upload grafana/dashboard.json
```

## Cleanup

```bash
# Delete deployments
kubectl delete -f manifests/base/ --ignore-not-found=true

# Delete monitoring stack (deployed via Helm)
helm uninstall prometheus --namespace monitoring --ignore-not-found=true
kubectl delete namespace monitoring --ignore-not-found=true

# Delete kind cluster
kind delete cluster --name dm-nkp-demo-cluster

# Or keep cluster for inspection
# (just don't run the delete command)
```

## Expected Results

After completing all steps, you should see:

✅ Application running with 2 replicas  
✅ Prometheus scraping metrics  
✅ Grafana dashboard showing metrics  
✅ Real-time updates as you generate traffic  

## Next Steps

- Customize the dashboard in Grafana
- Add alerts in Prometheus
- Deploy to production using Helm chart
- Integrate with your existing monitoring stack

## Quick Reference

```bash
# All-in-one commands
./scripts/run-e2e-demo.sh                    # Automated setup
make e2e-tests                                # Run e2e tests
kubectl port-forward -n monitoring svc/grafana 3000:3000  # Access Grafana
```

