# Deployment Guide

This guide covers deploying dm-nkp-gitops-custom-app to Kubernetes.

## Prerequisites

- Kubernetes cluster (1.20+)
- kubectl configured
- Helm 3.x (for Helm deployments)
- Access to container registry (ghcr.io)

## Deployment Options

### Option 1: Helm Chart (Recommended)

#### Install from Local Chart

```bash
# Package the chart
make helm-chart

# Install
helm install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  --create-namespace
```

#### Install from OCI Registry

```bash
helm install dm-nkp-gitops-custom-app \
  oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app \
  --version 0.1.0 \
  --namespace default \
  --create-namespace
```

#### Customize Values

Create a `values-custom.yaml`:

```yaml
replicaCount: 3
image:
  tag: "0.1.0"
service:
  type: LoadBalancer
resources:
  limits:
    cpu: 500m
    memory: 512Mi
```

Install with custom values:

```bash
helm install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  -f values-custom.yaml
```

### Option 2: Kubernetes Manifests

#### Deploy Base Resources

```bash
kubectl apply -f manifests/base/
```

#### Verify Deployment

```bash
kubectl get pods -l app=dm-nkp-gitops-custom-app
kubectl get svc dm-nkp-gitops-custom-app
```

## Ingress Configuration

### Traefik IngressRoute

If using Traefik as ingress controller:

```bash
kubectl apply -f manifests/traefik/ingressroute.yaml
```

Update the hostname in `ingressroute.yaml` to match your domain.

### Gateway API HTTPRoute

If using Gateway API:

1. Ensure Gateway API CRDs are installed
2. Deploy the HTTPRoute:

```bash
kubectl apply -f manifests/gateway-api/httproute.yaml
```

3. Or use envsubst for templating:

```bash
export APP_NAME=dm-nkp-gitops-custom-app
export NAMESPACE=default
export GATEWAY_NAME=traefik
export GATEWAY_NAMESPACE=traefik-system
export HOSTNAME=dm-nkp-gitops-custom-app.local
export HTTP_PORT=8080
export METRICS_PORT=9090

envsubst < manifests/gateway-api/httproute-template.yaml | kubectl apply -f -
```

## Prometheus Integration

### ServiceMonitor

If using Prometheus Operator, the Helm chart includes a ServiceMonitor:

```yaml
prometheus:
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
```

Or deploy manually:

```bash
kubectl apply -f chart/dm-nkp-gitops-custom-app/templates/servicemonitor.yaml
```

### Manual Scrape Configuration

Add to Prometheus scrape config:

```yaml
scrape_configs:
  - job_name: 'dm-nkp-gitops-custom-app'
    kubernetes_sd_configs:
      - role: endpoints
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        action: keep
        regex: dm-nkp-gitops-custom-app
```

## Verification

### Check Pods

```bash
kubectl get pods -l app=dm-nkp-gitops-custom-app
kubectl logs -l app=dm-nkp-gitops-custom-app
```

### Port Forward and Test

```bash
# Port forward to service
kubectl port-forward svc/dm-nkp-gitops-custom-app 8080:8080 9090:9090

# Test endpoints
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:9090/metrics
```

### Check Metrics

```bash
# Port forward metrics
kubectl port-forward svc/dm-nkp-gitops-custom-app 9090:9090

# Query metrics
curl http://localhost:9090/metrics | grep http_requests_total
```

## Scaling

### Manual Scaling

```bash
kubectl scale deployment/dm-nkp-gitops-custom-app --replicas=3
```

### Horizontal Pod Autoscaler

Enable in Helm values:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
```

Or apply HPA manifest:

```bash
kubectl apply -f chart/dm-nkp-gitops-custom-app/templates/hpa.yaml
```

## Upgrades

### Using Helm

```bash
# Upgrade with new version
helm upgrade dm-nkp-gitops-custom-app \
  oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app \
  --version 0.2.0

# Or with local chart
helm upgrade dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app
```

### Rolling Update

```bash
kubectl set image deployment/dm-nkp-gitops-custom-app \
  app=ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.2.0
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod -l app=dm-nkp-gitops-custom-app

# Check logs
kubectl logs -l app=dm-nkp-gitops-custom-app
```

### Service Not Accessible

```bash
# Check service endpoints
kubectl get endpoints dm-nkp-gitops-custom-app

# Check service
kubectl describe svc dm-nkp-gitops-custom-app
```

### Metrics Not Scraped

```bash
# Verify ServiceMonitor
kubectl get servicemonitor

# Check Prometheus targets (if Prometheus UI accessible)
# Should show dm-nkp-gitops-custom-app as a target
```

## Uninstallation

### Helm

```bash
helm uninstall dm-nkp-gitops-custom-app
```

### Kubernetes Manifests

```bash
kubectl delete -f manifests/
```
