# Helm-Based Deployment Guide

This guide explains how to deploy the application and its dependencies (Prometheus, Grafana, Traefik) using Helm charts instead of raw YAML manifests.

## Overview

Instead of using raw Kubernetes manifests, we use Helm charts for:
- **Prometheus** - via `kube-prometheus-stack` chart
- **Grafana** - via `grafana` chart (or included in kube-prometheus-stack)
- **Traefik** - via `traefik` chart
- **Gateway API** - via Traefik with Gateway API support

## Prerequisites

- Helm 3.x installed
- kubectl configured
- Kubernetes cluster (or kind cluster)

## Quick Start

### 1. Install Monitoring Stack

```bash
# Automated script
make setup-monitoring-helm

# Or manually
./scripts/setup-monitoring-helm.sh
```

This installs:
- Prometheus Operator (kube-prometheus-stack)
- Grafana
- ServiceMonitor CRDs
- PrometheusRule CRDs

### 2. Install Traefik

```bash
# Automated script
make setup-traefik-helm

# Or manually
./scripts/setup-traefik-helm.sh
```

### 3. Install Gateway API (Optional)

```bash
# Automated script
make setup-gateway-api-helm

# Or manually
./scripts/setup-gateway-api-helm.sh
```

## Detailed Setup

### Monitoring Stack (Prometheus + Grafana)

#### Using kube-prometheus-stack (Recommended)

The `kube-prometheus-stack` chart includes:
- Prometheus Operator
- Prometheus
- Grafana
- ServiceMonitor CRDs
- AlertManager (optional)

```bash
# Add repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.retention=200h \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort=30090 \
  --wait --timeout=5m
```

#### Standalone Grafana (if needed)

```bash
# Add repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install
helm upgrade --install grafana grafana/grafana \
  --namespace monitoring \
  --create-namespace \
  --set adminPassword=admin \
  --set service.type=NodePort \
  --set service.nodePort=30300 \
  --set persistence.enabled=false \
  --wait --timeout=5m
```

### Traefik

```bash
# Add repository
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Install
helm upgrade --install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443 \
  --set service.type=NodePort \
  --set ingressClass.enabled=true \
  --set ingressClass.isDefaultClass=true \
  --wait --timeout=5m
```

### Gateway API with Traefik

```bash
# Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Install Traefik with Gateway API support
helm upgrade --install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  --set experimental.kubernetesGateway.enabled=true \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443 \
  --set service.type=NodePort \
  --wait --timeout=5m
```

## Deploying the Application

### Using Helm Chart

```bash
# Install application
helm install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app

# Or with custom values
helm install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  -f chart/dm-nkp-gitops-custom-app/values-monitoring.yaml
```

### ServiceMonitor Integration

The application's Helm chart includes a ServiceMonitor that works with kube-prometheus-stack:

```yaml
# In values.yaml
prometheus:
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
    path: /metrics
    port: metrics
```

When you install the app with `prometheus.serviceMonitor.enabled=true`, Prometheus will automatically discover and scrape metrics.

## Accessing Services

### Prometheus

```bash
# Port forward
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Or via NodePort (if configured)
# http://<node-ip>:30090
```

### Grafana

```bash
# Port forward
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Or via NodePort (if configured)
# http://<node-ip>:30300

# Login
# Username: admin
# Password: admin (or check with: kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 -d)
```

### Traefik

```bash
# Port forward
kubectl port-forward -n traefik-system svc/traefik 8080:80

# Dashboard
# http://localhost:8080/dashboard/
```

## Importing Grafana Dashboard

After Grafana is installed:

1. **Access Grafana UI** (see above)

2. **Import Dashboard**:
   - Go to Dashboards → Import
   - Upload `grafana/dashboard.json`
   - Select Prometheus datasource
   - Click Import

3. **Or use Grafana API**:
   ```bash
   # Get Grafana admin password
   GRAFANA_PASSWORD=$(kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 -d)
   
   # Import dashboard
   curl -X POST \
     -u admin:$GRAFANA_PASSWORD \
     -H "Content-Type: application/json" \
     -d @grafana/dashboard.json \
     http://localhost:3000/api/dashboards/db
   ```

## Configuration Examples

### Custom Prometheus Retention

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.retention=7d
```

### Custom Grafana Configuration

```bash
helm upgrade grafana grafana/grafana \
  --namespace monitoring \
  --set grafana.ini.security.admin_user=admin \
  --set grafana.ini.security.admin_password=secure-password
```

### Traefik with Custom Configuration

```bash
helm upgrade traefik traefik/traefik \
  --namespace traefik-system \
  --set additionalArguments[0]=--api.dashboard=true \
  --set additionalArguments[1]=--api.insecure=true
```

## Upgrading

```bash
# Update Helm repos
helm repo update

# Upgrade monitoring stack
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring

# Upgrade Grafana
helm upgrade grafana grafana/grafana \
  --namespace monitoring

# Upgrade Traefik
helm upgrade traefik traefik/traefik \
  --namespace traefik-system
```

## Uninstalling

```bash
# Uninstall monitoring
helm uninstall prometheus -n monitoring
helm uninstall grafana -n monitoring

# Uninstall Traefik
helm uninstall traefik -n traefik-system

# Remove namespaces
kubectl delete namespace monitoring
kubectl delete namespace traefik-system
```

## Advantages of Helm Charts

### vs Raw Manifests

| Feature | Helm Charts | Raw Manifests |
|---------|-------------|---------------|
| **Versioning** | ✅ Chart versions | ❌ Manual tracking |
| **Updates** | ✅ `helm upgrade` | ❌ Manual edits |
| **Configuration** | ✅ values.yaml | ❌ Edit files |
| **Dependencies** | ✅ Chart dependencies | ❌ Manual management |
| **Rollback** | ✅ `helm rollback` | ❌ Manual |
| **Packaging** | ✅ OCI registry | ❌ Git repos |

### Benefits

1. **Easy Updates**: `helm repo update && helm upgrade`
2. **Configuration**: Customize via values.yaml
3. **Versioning**: Track chart versions
4. **Rollback**: Easy rollback to previous versions
5. **Community**: Well-maintained charts
6. **CI/CD**: Easy to integrate in pipelines

## Troubleshooting

### Prometheus Not Scraping

```bash
# Check ServiceMonitor
kubectl get servicemonitor -A

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090/targets

# Check Prometheus logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus
```

### Grafana Can't Connect to Prometheus

```bash
# Check Grafana datasource
kubectl get configmap -n monitoring grafana -o yaml

# Check Prometheus service
kubectl get svc -n monitoring | grep prometheus

# Test connectivity from Grafana pod
kubectl exec -n monitoring -it deployment/grafana -- wget -qO- http://prometheus-kube-prometheus-prometheus:9090/api/v1/status/config
```

### Traefik Not Working

```bash
# Check Traefik pods
kubectl get pods -n traefik-system

# Check Traefik logs
kubectl logs -n traefik-system -l app.kubernetes.io/name=traefik

# Check IngressClass
kubectl get ingressclass
```

## Makefile Targets

```bash
make setup-monitoring-helm    # Install Prometheus + Grafana via Helm
make setup-traefik-helm      # Install Traefik via Helm
make setup-gateway-api-helm  # Install Gateway API + Traefik via Helm
```

## Resources

- [kube-prometheus-stack Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Grafana Helm Chart](https://github.com/grafana/helm-charts/tree/main/charts/grafana)
- [Traefik Helm Chart](https://github.com/traefik/traefik-helm-chart)
- [Gateway API](https://gateway-api.sigs.k8s.io/)

