# Gateway API Path-Based Routing for Observability Services

## Overview

This document explains how to expose all observability services (Grafana, Prometheus, Loki, Tempo, OTel Collector) through a single external entrypoint using path-based routing with Gateway API HTTPRoutes.

## MetalLB Configuration

### Production (NKP Platform)

**❌ Do NOT install MetalLB** - It should already be present in the NKP platform where you'll be deploying this application in production. MetalLB provides LoadBalancer IP addresses to services in the cluster.

### Local Testing

**For local testing (kind/minikube), you have three options:**

#### Option 1: Port-Forwarding (Simplest, No MetalLB needed)

Use `kubectl port-forward` to access services locally. This is the simplest option for local testing:

```bash
# Access services via port-forwarding (no MetalLB needed)
kubectl port-forward -n traefik-system svc/traefik 8080:80
# Then access: http://localhost:8080/grafana/
```

**Pros:** Simple, works everywhere, no setup required  
**Cons:** Not testing production setup, requires separate port-forward for each service

#### Option 2: NodePort (Recommended for Local Testing)

Use NodePort for Traefik service instead of LoadBalancer. Update Traefik service to use NodePort:

```bash
# For Traefik installed via Helm
helm upgrade --install traefik traefik/traefik \
  --namespace traefik-system \
  --set service.type=NodePort \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443
```

Then access services via NodePort:

```bash
# Get kind node IP
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(kind get nodes --name <cluster-name> | head -n1)

# Access services
http://<node-ip>:30080/grafana/
http://<node-ip>:30080/prometheus/
```

**Pros:** Tests Gateway/HTTPRoute setup, single entrypoint, no MetalLB needed  
**Cons:** Need to know node IP, port numbers are not standard (30080+)

#### Option 3: Install MetalLB in Kind (Production-Like)

If you want to test the exact production setup, you can install MetalLB in your kind cluster using Helm:

**Using the setup script (Recommended):**

```bash
# Install MetalLB via Helm script
./scripts/setup-metallb-helm.sh <cluster-name> [ip-pool-start] [ip-pool-end]

# Example:
./scripts/setup-metallb-helm.sh dm-nkp-demo-cluster 172.18.255.200 172.18.255.250

# Or using Makefile:
make setup-metallb-helm
```

**Manual installation via Helm:**

```bash
# Add MetalLB Helm repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Create namespace
kubectl create namespace metallb-system

# Install MetalLB
helm upgrade --install metallb bitnami/metallb \
  --namespace metallb-system \
  --set configInline.address-pools[0].name=default \
  --set configInline.address-pools[0].protocol=layer2 \
  --set configInline.address-pools[0].addresses[0]="172.18.255.200-172.18.255.250" \
  --wait --timeout=5m

# Detect Docker network subnet for kind (to configure IP pool correctly)
docker network inspect kind | jq -r '.[0].IPAM.Config[0].Subnet'

# Update Traefik service to LoadBalancer
kubectl patch svc traefik -n traefik-system -p '{"spec":{"type":"LoadBalancer"}}'

# Get LoadBalancer IP
kubectl get svc traefik -n traefik-system
```

**Alternative: Using kubectl manifests (if Helm chart doesn't work):**

```bash
# Install MetalLB via kubectl
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# Wait for MetalLB to be ready
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s

# Configure IP address pool
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.255.200-172.18.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF
```

**Pros:** Exact production setup, standard LoadBalancer IPs, tests full stack  
**Cons:** Requires MetalLB installation and configuration

**Recommendation:** Use **Option 1 (Port-Forwarding)** for quick local development, or **Option 2 (NodePort)** for testing Gateway/HTTPRoute setup without MetalLB complexity.

## Architecture

```
External Entrypoint (via MetalLB LoadBalancer IP)
    ↓
Traefik Gateway (with Gateway API support)
    ↓
HTTPRoute (path-based routing)
    ├── /grafana → Grafana Service (port 3000)
    ├── /prometheus → Prometheus Service (port 80/9090)
    ├── /loki → Loki Service (port 3100)
    ├── /tempo → Tempo Service (port 3200)
    └── /otel-collector → OTel Collector Service (port 4318)
```

## Prerequisites

1. **MetalLB**: Already present in NKP platform (provides LoadBalancer IPs)
2. **Traefik with Gateway API**: Pre-deployed in NKP platform (namespace: `traefik-system`)
3. **Gateway API CRDs**: Installed via Mesosphere Kommander (version 1.11.1)
4. **Gateway Resource**: Created by Traefik (name: `traefik`)

## Configuration

### 1. Enable Gateway Routing

In `chart/observability-stack/values.yaml`, enable the gateway configuration:

```yaml
gateway:
  enabled: true  # Set to true to enable HTTPRoute resources
  parentRef:
    name: "traefik"  # Gateway name (verify: kubectl get gateway -A)
    namespace: "traefik-system"  # Gateway namespace (verify in your cluster)
  hostname: "observability.local"  # External hostname for all services
```

### 2. Configure Service Names

Update service names to match your actual services in the cluster:

```yaml
services:
  grafana:
    name: "grafana"  # Update to match your Grafana service name
    namespace: ""  # Empty = same as Release namespace, or specify different namespace
    port: 3000
    path: "/grafana"
  prometheus:
    name: "prometheus-server"  # For kube-prometheus-stack: <release-name>-kube-prometheus-prometheus
    namespace: ""  # Or "monitoring" if in different namespace
    port: 80  # Or 9090 for direct Prometheus
    path: "/prometheus"
  # ... etc
```

**Verify service names:**

```bash
kubectl get svc -A | grep -E "(grafana|prometheus|loki|tempo)"
```

### 3. Service-Specific Configuration

#### Grafana

Grafana requires `root_url` configuration for subpath support. Configure in Grafana Helm chart values:

```yaml
grafana:
  env:
    GF_SERVER_ROOT_URL: "%(protocol)s://%(domain)s:%(http_port)s/grafana/"
  # Or via ConfigMap:
  server:
    root_url: "%(protocol)s://%(domain)s:%(http_port)s/grafana/"
```

Access Grafana at: `http://observability.local/grafana/`

#### Prometheus

Prometheus may need external URL configuration for subpath support:

```yaml
prometheus:
  prometheusSpec:
    externalUrl: "http://observability.local/prometheus/"
    routePrefix: "/prometheus/"
```

Access Prometheus at: `http://observability.local/prometheus/`

#### Loki

Loki Gateway typically supports subpath routing out of the box. Access at: `http://observability.local/loki/`

#### Tempo

Tempo works with path-based routing. Access at: `http://observability.local/tempo/`

#### OTel Collector

OTel Collector endpoints:

- Health: `http://observability.local/otel-collector/`
- Traces: `http://observability.local/otel-collector/v1/traces`
- Metrics: `http://observability.local/otel-collector/v1/metrics`
- Logs: `http://observability.local/otel-collector/v1/logs`
- Prometheus metrics: `http://observability.local/otel-collector/metrics`

## Deployment

### For Local Testing (kind/minikube)

If setting up for local testing, install MetalLB first:

```bash
# Option 1: Using Makefile
make setup-metallb-helm

# Option 2: Using script directly
./scripts/setup-metallb-helm.sh <cluster-name> [ip-pool-start] [ip-pool-end]

# Example:
./scripts/setup-metallb-helm.sh dm-nkp-demo-cluster 172.18.255.200 172.18.255.250

# Then update Traefik service to LoadBalancer
kubectl patch svc traefik -n traefik-system -p '{"spec":{"type":"LoadBalancer"}}'
```

### 1. Verify Prerequisites

```bash
# Verify Gateway API CRDs are installed
kubectl get crd | grep gateway.networking.k8s.io

# Verify Gateway resource exists
kubectl get gateway -A

# Verify Traefik service has LoadBalancer IP (MetalLB)
kubectl get svc -n traefik-system traefik
```

### 2. Deploy Observability Stack with Gateway Enabled

```bash
helm upgrade --install observability-stack ./chart/observability-stack \
  --namespace observability \
  --create-namespace \
  --set gateway.enabled=true \
  --set gateway.hostname=observability.local \
  --set gateway.services.grafana.name=<your-grafana-service> \
  --set gateway.services.prometheus.name=<your-prometheus-service>
```

### 3. Verify HTTPRoute Resources

```bash
# Check HTTPRoute was created
kubectl get httproute -n observability

# Describe HTTPRoute for details
kubectl describe httproute <observability-stack-name>-observability -n observability
```

### 4. Get External IP

```bash
# Get LoadBalancer IP from Traefik service
kubectl get svc -n traefik-system traefik

# Or if using specific hostname with DNS
# Add DNS entry pointing to LoadBalancer IP: observability.local -> <LOADBALANCER_IP>
```

## Accessing Services

Once deployed, all services are accessible via the same hostname with different paths:

```
http://<LOADBALANCER_IP>/grafana/
http://<LOADBALANCER_IP>/prometheus/
http://<LOADBALANCER_IP>/loki/
http://<LOADBALANCER_IP>/tempo/
http://<LOADBALANCER_IP>/otel-collector/
```

Or with DNS configured:

```
http://observability.local/grafana/
http://observability.local/prometheus/
http://observability.local/loki/
http://observability.local/tempo/
http://observability.local/otel-collector/
```

## Benefits of Path-Based Routing

1. **Single Entrypoint**: One external IP/hostname for all services
2. **Consistent Access**: Easy to remember and configure
3. **Simplified Security**: Single point for authentication/authorization (can add later)
4. **No Port Forwarding**: Eliminates need for `kubectl port-forward`
5. **Production-Ready**: Aligns with production NKP platform setup

## Troubleshooting

### HTTPRoute Not Working

1. **Verify Gateway exists:**

   ```bash
   kubectl get gateway -n traefik-system
   ```

2. **Check HTTPRoute status:**

   ```bash
   kubectl describe httproute <route-name> -n <namespace>
   ```

3. **Verify service names match:**

   ```bash
   kubectl get svc -A | grep <service-name>
   ```

### Service Returns 404

- **Grafana**: Ensure `GF_SERVER_ROOT_URL` is configured for subpath
- **Prometheus**: Ensure `externalUrl` is configured for subpath
- **Path mismatch**: Verify path in HTTPRoute matches service expectations

### Cannot Access External IP

1. **Check LoadBalancer IP assignment:**

   ```bash
   kubectl get svc -n traefik-system traefik
   ```

2. **Verify MetalLB is running:**

   ```bash
   kubectl get pods -n metallb-system
   ```

3. **Check MetalLB IP pool configuration** (if IP not assigned)

## Alternative: Multiple HTTPRoutes

You can also create separate HTTPRoute resources for each service (instead of one combined HTTPRoute). This is useful if:

- Services are in different namespaces
- Different security policies per service
- Different hostnames per service

To use separate HTTPRoutes, you would create individual HTTPRoute files in the templates directory for each service. The current implementation uses a single HTTPRoute with multiple rules for simplicity.

## References

- [Gateway API Specification](https://gateway-api.sigs.k8s.io/)
- [Traefik Gateway API Support](https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/)
- [MetalLB Documentation](https://metallb.universe.tf/)
