# NKP Compatibility Check - Verification Results

## ✅ Good News: No Chart Template Changes Required!

**Your app chart templates are already compatible with NKP, OpenTelemetry Operator, and Mesosphere Kommander Applications!** All configuration is driven by `values.yaml`, so you only need to update the **ConfigMap values** in your FluxCD HelmRelease.

### Platform Services from Mesosphere Kommander

Your NKP platform uses [Mesosphere Kommander Applications](https://github.com/mesosphere/kommander-applications):
- ✅ **Gateway API CRDs**: [gateway-api-crds/1.11.1](https://github.com/mesosphere/kommander-applications/tree/main/applications/gateway-api-crds/1.11.1) - ✅ **Compatible** (HTTPRoute uses `gateway.networking.k8s.io/v1`)
- ✅ **Traefik**: [traefik/37.1.2](https://github.com/mesosphere/kommander-applications/tree/main/applications/traefik/37.1.2) - ✅ **Compatible** (Gateway implementation)
- ✅ **Grafana Loki**: [project-grafana-loki/0.80.5](https://github.com/mesosphere/kommander-applications/tree/main/applications/project-grafana-loki/0.80.5) - ✅ **Compatible**
- ✅ **kube-prometheus-stack**: [kube-prometheus-stack/78.4.0](https://github.com/mesosphere/kommander-applications/tree/main/applications/kube-prometheus-stack/78.4.0) - ✅ **Compatible**

**Compatibility Status**: ✅ **FULLY COMPATIBLE** - All Mesosphere Kommander Applications use standard Helm chart naming conventions that your app chart supports. Your HTTPRoute template uses `gateway.networking.k8s.io/v1` API version which is compatible with Gateway API CRDs v1.11.1.

## Changes Required for NKP Deployment

### Summary of Required Changes

| Component | Current Default | NKP Required | Action Required |
|-----------|----------------|--------------|-----------------|
| **OTel Collector Endpoint** | `otel-collector.observability.svc.cluster.local:4317` | `collector.opentelemetry.svc.cluster.local:4317` | ⚠️ **UPDATE ConfigMap** |
| **OTel Namespace** | `observability` | `opentelemetry` | ⚠️ **UPDATE ConfigMap** |
| **ServiceMonitor Labels** | `component: otel-collector` | `app.kubernetes.io/name: opentelemetry-collector` + `app.kubernetes.io/component: collector` | ⚠️ **UPDATE ConfigMap** |
| **ServiceMonitor Namespace** | `observability` | `monitoring` (verify in your cluster) | ⚠️ **UPDATE ConfigMap** |
| **Prometheus Port Name** | `prometheus` | `otlp` (verify in your cluster) | ⚠️ **VERIFY & UPDATE ConfigMap** |
| **Grafana Namespace** | `observability` | `monitoring` (verify in your cluster) | ⚠️ **VERIFY & UPDATE ConfigMap** |

### What DOESN'T Need Changes

✅ **Chart Templates** - All templates use `.Values`, so they're flexible  
✅ **Chart Structure** - No changes needed  
✅ **ServiceMonitor Template** - Already supports custom labels via `selectorLabels`  
✅ **Deployment Template** - Already supports custom OTLP endpoint via `opentelemetry.env`  
✅ **HTTPRoute Template** - Already configurable via `gateway.parentRef`  

## Quick Start: ConfigMap for FluxCD

Based on your [HelmRelease](https://github.com/deepak-muley/dm-nkp-gitops-app-catalog/blob/main/applications/dm-nkp-gitops-custom-app/0.1.0/helmrelease/helmrelease.yaml), you need to create a ConfigMap named `${releaseName}-config-defaults`.

### Step 1: Verify OpenTelemetry Operator Setup

```bash
# Check if OpenTelemetry Operator is installed
kubectl get pods -n opentelemetry

# Find the collector service name
kubectl get svc -n opentelemetry | grep collector

# Verify service labels (should match OpenTelemetry Operator standards)
kubectl get svc <collector-service-name> -n opentelemetry -o yaml | grep -A 5 labels
```

### Step 2: Verify kube-prometheus-stack (Mesosphere Kommander)

```bash
# Find Prometheus namespace (kube-prometheus-stack)
kubectl get deployment -A | grep prometheus

# Find Prometheus service name (pattern: <release-name>-kube-prometheus-prometheus)
kubectl get svc -A | grep prometheus | grep -v prometheus-operated

# Common service names:
# - kube-prometheus-stack-prometheus
# - prometheus-kube-prometheus-prometheus

# Find Grafana namespace (part of kube-prometheus-stack)
kubectl get deployment -A | grep grafana

# Find Grafana service name (pattern: <release-name>-grafana)
kubectl get svc -A | grep grafana

# Common service names:
# - kube-prometheus-stack-grafana
# - prometheus-grafana

# Verify HelmRelease targetNamespace
kubectl get helmrelease -A | grep prometheus
```

### Step 3: Verify Grafana Loki (Mesosphere Kommander)

```bash
# Find Loki namespace (project-grafana-loki)
kubectl get deployment -A | grep loki

# Find Loki service names (project-grafana-loki creates gateway and main service)
kubectl get svc -A | grep loki

# Common service names:
# - project-grafana-loki-gateway (gateway service, port 80)
# - project-grafana-loki (main service, port 3100)

# Verify HelmRelease targetNamespace
kubectl get helmrelease -A | grep loki
```

### Step 4: Verify Gateway API CRDs (Mesosphere Kommander)

```bash
# Verify Gateway API CRDs are installed (gateway-api-crds/1.11.1)
kubectl get crd | grep gateway.networking.k8s.io

# Should see CRDs like:
# - gateways.gateway.networking.k8s.io
# - httproutes.gateway.networking.k8s.io
# - referencegrants.gateway.networking.k8s.io

# Verify HTTPRoute CRD supports v1 API (required for your HTTPRoute)
kubectl get crd httproutes.gateway.networking.k8s.io -o jsonpath='{.spec.versions[*].name}'
# Should include: v1

# Verify Gateway API CRDs HelmRelease
kubectl get helmrelease -A | grep gateway-api
```

### Step 5: Verify Traefik (Mesosphere Kommander)

```bash
# Find Traefik namespace
kubectl get deployment -A | grep traefik

# Find Traefik service
kubectl get svc -A | grep traefik

# Common service names:
# - traefik

# Find Gateway API Gateway resource (requires Gateway API CRDs from Step 4)
kubectl get gateway -A

# Common Gateway names:
# - traefik

# Verify HelmRelease targetNamespace
kubectl get helmrelease -A | grep traefik
```

### Step 6: Create ConfigMap

Use `values-nkp.yaml` as a base and adjust based on your verification:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${releaseName}-config-defaults  # Match your HelmRelease valuesFrom
  namespace: ${releaseNamespace}
data:
  values.yaml: |
    # Copy from chart/dm-nkp-gitops-custom-app/values-nkp.yaml
    # Update these values based on Step 1 & 2 verification:
    
    opentelemetry:
      enabled: true
      collector:
        endpoint: "<verify-collector-service-name>.opentelemetry.svc.cluster.local:4317"
      env:
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "<verify-collector-service-name>.opentelemetry.svc.cluster.local:4317"
        - name: OTEL_SERVICE_NAME
          value: "dm-nkp-gitops-custom-app"
        - name: OTEL_EXPORTER_OTLP_INSECURE
          value: "false"  # Use TLS if configured
    
    monitoring:
      serviceMonitor:
        enabled: true
        namespace: "<verify-prometheus-namespace>"  # e.g., "monitoring"
        otelCollector:
          selectorLabels:
            app.kubernetes.io/name: opentelemetry-collector
            app.kubernetes.io/component: collector
          namespace: "opentelemetry"
          prometheusPort: "<verify-port-name>"  # e.g., "otlp" or "prometheus"
          prometheusPath: "/metrics"
    
    gateway:
      enabled: true
      parentRef:
        name: "<verify-gateway-name>"  # e.g., "traefik"
        namespace: "<verify-gateway-namespace>"  # e.g., "traefik-system"
      hostnames:
        - "<your-production-hostname>"
    
    grafana:
      dashboards:
        enabled: true
        namespace: "<verify-grafana-namespace>"  # e.g., "monitoring"
        folder: "/Applications"
```

## Detailed Verification Checklist

### ✅ OpenTelemetry Operator Compatibility

- [ ] OpenTelemetry Operator is installed in `opentelemetry` namespace
- [ ] OpenTelemetryCollector CR exists (check: `kubectl get opentelemetrycollector -n opentelemetry`)
- [ ] Collector service exists (check: `kubectl get svc -n opentelemetry | grep collector`)
- [ ] Service name identified: `_____________________`
- [ ] Service labels match: `app.kubernetes.io/name: opentelemetry-collector`
- [ ] Port name identified: `_____________________` (check: `kubectl get svc <service-name> -n opentelemetry -o yaml`)

### ✅ Namespace Verification

- [ ] Prometheus Operator namespace: `_____________________`
- [ ] Grafana namespace: `_____________________`
- [ ] Traefik Gateway namespace: `_____________________`
- [ ] Traefik Gateway name: `_____________________`

### ✅ ConfigMap Values

- [ ] OTel Collector endpoint updated: `_____________________`
- [ ] ServiceMonitor namespace updated: `_____________________`
- [ ] ServiceMonitor selectorLabels updated: `_____________________`
- [ ] Prometheus port name verified: `_____________________`
- [ ] Gateway configuration verified: `_____________________`
- [ ] Grafana namespace verified: `_____________________`
- [ ] Production hostname configured: `_____________________`

## Testing After Deployment

### 1. Verify App Pods Are Running

```bash
kubectl get pods -n <app-namespace> -l app.kubernetes.io/name=dm-nkp-gitops-custom-app
```

### 2. Check OTLP Connection

```bash
# Check app pod logs for OTLP connection
kubectl logs -n <app-namespace> <app-pod-name> | grep -i otel

# Should see successful OTLP connection (no errors)
```

### 3. Verify ServiceMonitor Created

```bash
# Check ServiceMonitor exists in Prometheus namespace
kubectl get servicemonitor -n <prometheus-namespace> | grep dm-nkp-gitops-custom-app

# Verify ServiceMonitor configuration
kubectl get servicemonitor <service-monitor-name> -n <prometheus-namespace> -o yaml
```

### 4. Verify Metrics in Prometheus

```bash
# Port-forward to Prometheus
kubectl port-forward -n <prometheus-namespace> svc/<prometheus-service> 9090:9090

# Query Prometheus (open browser to http://localhost:9090)
# Search for metrics with prefix: otelcol_
```

### 5. Verify Grafana Dashboards

```bash
# Check dashboard ConfigMaps
kubectl get configmap -n <grafana-namespace> -l grafana_dashboard=1 | grep dm-nkp-gitops-custom-app

# Port-forward to Grafana and verify dashboards appear
kubectl port-forward -n <grafana-namespace> svc/<grafana-service> 3000:80
# Open browser to http://localhost:3000 and check for application dashboards
```

## Common Issues

### Issue: Cannot Connect to Collector

**Check:**
```bash
# Verify collector service exists
kubectl get svc -n opentelemetry

# Test connection from app pod
kubectl exec -it <app-pod> -n <app-namespace> -- \
  nc -zv <collector-service-name>.opentelemetry.svc.cluster.local 4317
```

**Solution:** Update ConfigMap with correct service name and namespace.

### Issue: ServiceMonitor Not Finding Collector

**Check:**
```bash
# Verify ServiceMonitor namespace matches Prometheus Operator namespace
kubectl get servicemonitor -n <prometheus-namespace>

# Verify selector labels match collector service labels
kubectl get svc <collector-service-name> -n opentelemetry -o jsonpath='{.metadata.labels}'
```

**Solution:** Update `monitoring.serviceMonitor.otelCollector.selectorLabels` in ConfigMap to match actual service labels.

### Issue: Prometheus Not Scraping

**Check:**
```bash
# Verify port name exists on collector service
kubectl get svc <collector-service-name> -n opentelemetry -o yaml | grep -A 5 ports

# Verify ServiceMonitor port name matches
kubectl get servicemonitor <service-monitor-name> -n <prometheus-namespace> -o yaml | grep -A 3 port
```

**Solution:** Update `monitoring.serviceMonitor.otelCollector.prometheusPort` in ConfigMap to match actual port name.

## Files Provided for NKP

✅ **`chart/dm-nkp-gitops-custom-app/values-nkp.yaml`** - NKP-specific values template  
✅ **`docs/NKP_DEPLOYMENT.md`** - Complete NKP deployment guide  
✅ **`docs/NKP_COMPATIBILITY_CHECK.md`** - This file (verification checklist)  

## Mesosphere Kommander Application Service Naming

### kube-prometheus-stack (78.4.0)

**Service Naming Pattern:**
- Prometheus: `<release-name>-kube-prometheus-prometheus`
- Grafana: `<release-name>-grafana`

**Common Release Names:**
- `kube-prometheus-stack` → Services: `kube-prometheus-stack-prometheus`, `kube-prometheus-stack-grafana`
- `prometheus` → Services: `prometheus-kube-prometheus-prometheus`, `prometheus-grafana`

**Verification:**
```bash
kubectl get svc -A | grep -E "prometheus|grafana" | grep -v prometheus-operated
```

### project-grafana-loki (0.80.5)

**Service Naming Pattern:**
- Gateway: `<release-name>-gateway` (port 80)
- Main Service: `<release-name>` (port 3100)

**Common Release Names:**
- `project-grafana-loki` → Services: `project-grafana-loki-gateway`, `project-grafana-loki`

**Verification:**
```bash
kubectl get svc -A | grep loki
```

**Loki URL for Grafana Datasource:**
- Gateway: `http://project-grafana-loki-gateway.<namespace>.svc.cluster.local:80`
- Main Service: `http://project-grafana-loki.<namespace>.svc.cluster.local:3100`

### gateway-api-crds (1.11.1)

**CRDs Installed:**
- `gateways.gateway.networking.k8s.io`
- `httproutes.gateway.networking.k8s.io`
- `referencegrants.gateway.networking.k8s.io`
- And other Gateway API CRDs

**API Version Compatibility:**
- ✅ Your HTTPRoute uses `gateway.networking.k8s.io/v1` (compatible with CRDs v1.11.1)
- ✅ HTTPRoute template is compatible with Gateway API CRDs v1.11.1

**Verification:**
```bash
# Verify CRDs are installed
kubectl get crd | grep gateway.networking.k8s.io

# Verify v1 API version is supported
kubectl get crd httproutes.gateway.networking.k8s.io -o jsonpath='{.spec.versions[*].name}'
# Should include: v1
```

### traefik (37.1.2)

**Service Naming Pattern:**
- Main Service: `traefik` (common default)

**Common Namespaces:**
- `traefik-system` (default)
- `traefik`
- `ingress`

**Gateway Resource:**
- Gateway name: `traefik` (common default)
- Requires Gateway API CRDs (from gateway-api-crds/1.11.1)

**Verification:**
```bash
kubectl get svc -A | grep traefik
kubectl get gateway -A  # Requires Gateway API CRDs
```

## Summary

**✅ Chart is Compatible:** No template changes needed  
**✅ Mesosphere Kommander Compatible:** All services follow standard Helm naming conventions  
**⚠️ Values Need Update:** Use `values-nkp.yaml` as base for your ConfigMap  
**✅ Verification Required:** Verify service names and namespaces in your NKP cluster  
**✅ ConfigMap Required:** Create ConfigMap with verified values for FluxCD HelmRelease  

**Mesosphere Kommander Services:**
- ✅ Gateway API CRDs (gateway-api-crds/1.11.1) - ✅ Compatible (HTTPRoute uses v1 API)
- ✅ Traefik (traefik/37.1.2) - ✅ Compatible (Gateway implementation)
- ✅ Grafana Loki (project-grafana-loki/0.80.5) - ✅ Compatible
- ✅ kube-prometheus-stack (78.4.0) - ✅ Compatible

**Gateway API Compatibility:**
- ✅ HTTPRoute template uses `gateway.networking.k8s.io/v1` API version
- ✅ Compatible with Gateway API CRDs v1.11.1 from Mesosphere Kommander
- ✅ No template changes needed

Your app chart is ready for NKP deployment once you update the ConfigMap values! 🚀
