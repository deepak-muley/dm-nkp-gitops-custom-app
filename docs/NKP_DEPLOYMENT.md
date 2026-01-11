# Deploying on Nutanix Kubernetes Platform (NKP) with FluxCD

## Overview

This guide covers deploying `dm-nkp-gitops-custom-app` on Nutanix Kubernetes Platform (NKP) using FluxCD with OpenTelemetry Operator.

## Prerequisites

Based on the referenced HelmRelease configurations:
- ✅ FluxCD is already deployed on NKP
- ✅ OpenTelemetry Operator will be installed via [NKP Product Catalog](https://github.com/nutanix-cloud-native/nkp-nutanix-product-catalog/blob/release-2.x/applications/opentelemetry-operator/0.93.0/helmrelease/opentelemetry.yaml)
- ✅ App will be deployed via [GitOps App Catalog](https://github.com/deepak-muley/dm-nkp-gitops-app-catalog/blob/main/applications/dm-nkp-gitops-custom-app/0.1.0/helmrelease/helmrelease.yaml)

### Platform Services from Mesosphere Kommander Applications

Your NKP platform uses [Mesosphere Kommander Applications](https://github.com/mesosphere/kommander-applications):
- ✅ **Gateway API CRDs**: [gateway-api-crds/1.11.1](https://github.com/mesosphere/kommander-applications/tree/main/applications/gateway-api-crds/1.11.1) - Required for HTTPRoute
- ✅ **Traefik**: [traefik/37.1.2](https://github.com/mesosphere/kommander-applications/tree/main/applications/traefik/37.1.2) - Gateway implementation
- ✅ **Grafana Loki**: [project-grafana-loki/0.80.5](https://github.com/mesosphere/kommander-applications/tree/main/applications/project-grafana-loki/0.80.5)
- ✅ **kube-prometheus-stack**: [kube-prometheus-stack/78.4.0](https://github.com/mesosphere/kommander-applications/tree/main/applications/kube-prometheus-stack/78.4.0)

**Compatibility**: ✅ Your app chart is fully compatible with these Mesosphere Kommander Applications. Your HTTPRoute uses `gateway.networking.k8s.io/v1` API version which is compatible with Gateway API CRDs v1.11.1. You only need to verify service names and namespaces in your cluster.

## Key Differences: OpenTelemetry Operator vs Direct OTel Collector

### What is OpenTelemetry Operator?

**OpenTelemetry Operator** is a Kubernetes operator that manages OpenTelemetry Collector instances via `OpenTelemetryCollector` Custom Resources (CRs). It's different from directly deploying an OTel Collector.

**Key Points:**
- Operator is installed in `opentelemetry` namespace (from the HelmRelease)
- Operator watches for `OpenTelemetryCollector` CRs
- When you create an `OpenTelemetryCollector` CR, the operator creates:
  - Deployment for the collector
  - Service for the collector (named `<cr-name>-collector`)

### Service Naming Convention

**OpenTelemetry Operator** service naming:
```
⚠️ IMPORTANT: Service name matches OpenTelemetryCollector CR name exactly (not Deployment name)
   - Service name = CR name
   - Deployment name = CR name + "-collector" suffix
```

**Common Examples:**
- CR named `collector` → Service: `collector.opentelemetry.svc.cluster.local` (Deployment: `collector-collector`)
- CR named `otelcol` → Service: `otelcol.opentelemetry.svc.cluster.local` (Deployment: `otelcol-collector`)
- CR named `opentelemetry-collector` → Service: `opentelemetry-collector.opentelemetry.svc.cluster.local` (Deployment: `opentelemetry-collector-collector`)

**Note**: The `-collector` suffix is only added to Deployment/StatefulSet names, NOT to the Service name. The Service name matches the CR name directly.

### Standard Labels Used by Operator

OpenTelemetry Operator uses standard Kubernetes labels:
```yaml
app.kubernetes.io/name: opentelemetry-collector
app.kubernetes.io/component: collector
app.kubernetes.io/managed-by: opentelemetry-operator
```

## Required Changes for NKP Compatibility

### 1. OTel Collector Endpoint

**Current Default (`values.yaml`):**
```yaml
opentelemetry:
  collector:
    endpoint: "otel-collector.observability.svc.cluster.local:4317"
```

**NKP Configuration (OpenTelemetry Operator):**
```yaml
opentelemetry:
  collector:
    # Update based on your OpenTelemetryCollector CR name
    endpoint: "collector.opentelemetry.svc.cluster.local:4317"
    # OR (if CR is named 'otelcol'):
    # endpoint: "otelcol.opentelemetry.svc.cluster.local:4317"
```

**Environment Variable:**
```yaml
opentelemetry:
  env:
    - name: OTEL_EXPORTER_OTLP_ENDPOINT
      value: "collector.opentelemetry.svc.cluster.local:4317"
```

### 2. ServiceMonitor Selector Labels

**Current Default (`values.yaml`):**
```yaml
monitoring:
  serviceMonitor:
    otelCollector:
      selectorLabels:
        component: otel-collector  # ❌ Not compatible with OpenTelemetry Operator
```

**NKP Configuration (OpenTelemetry Operator):**
```yaml
monitoring:
  serviceMonitor:
    otelCollector:
      selectorLabels:
        app.kubernetes.io/name: opentelemetry-collector  # ✅ OpenTelemetry Operator standard
        app.kubernetes.io/component: collector
      namespace: "opentelemetry"  # ✅ OpenTelemetry Operator namespace
```

### 3. Namespace References

**Current Default:**
- OTel Collector: `observability` namespace
- Prometheus/Grafana: `observability` namespace

**NKP Typical Configuration:**
- OTel Collector: `opentelemetry` namespace (from OpenTelemetry Operator HelmRelease)
- Prometheus/Grafana: `monitoring` namespace (verify in your NKP cluster)

### 4. Prometheus Port Name

**OpenTelemetry Operator** typically exposes metrics on port named `otlp` or `prometheus`. Verify in your cluster:
```bash
kubectl get svc -n opentelemetry <collector-service-name> -o yaml
```

## Configuration File for NKP

A pre-configured values file is provided: `chart/dm-nkp-gitops-custom-app/values-nkp.yaml`

This file includes:
- ✅ OpenTelemetry Operator compatible endpoints
- ✅ Correct namespace references for NKP
- ✅ OpenTelemetry Operator standard labels
- ✅ Production-ready defaults

## FluxCD HelmRelease Configuration

### Your Current HelmRelease

Based on the [reference HelmRelease](https://github.com/deepak-muley/dm-nkp-gitops-app-catalog/blob/main/applications/dm-nkp-gitops-custom-app/0.1.0/helmrelease/helmrelease.yaml):

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: dm-nkp-gitops-custom-app
  namespace: ${releaseNamespace}
spec:
  chartRef:
    kind: OCIRepository
    name: ${releaseName}-chart
  valuesFrom:
    - kind: ConfigMap
      name: ${releaseName}-config-defaults  # ← Values come from this ConfigMap
```

### ConfigMap Structure for NKP

Create a ConfigMap with NKP-compatible values:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${releaseName}-config-defaults
  namespace: ${releaseNamespace}
data:
  values.yaml: |
    # Copy contents from values-nkp.yaml and adjust based on your NKP setup
    opentelemetry:
      enabled: true
      collector:
        endpoint: "collector.opentelemetry.svc.cluster.local:4317"
      env:
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "collector.opentelemetry.svc.cluster.local:4317"
        - name: OTEL_SERVICE_NAME
          value: "dm-nkp-gitops-custom-app"
        - name: OTEL_EXPORTER_OTLP_INSECURE
          value: "false"  # Use TLS if configured
    
    monitoring:
      serviceMonitor:
        enabled: true
        namespace: "monitoring"  # Verify in your cluster
        otelCollector:
          selectorLabels:
            app.kubernetes.io/name: opentelemetry-collector
            app.kubernetes.io/component: collector
          namespace: "opentelemetry"
          prometheusPort: "otlp"  # Verify port name in your cluster
    
    gateway:
      enabled: true
      parentRef:
        name: "traefik"  # Verify Gateway name
        namespace: "traefik-system"  # Verify namespace
      hostnames:
        - "dm-nkp-gitops-custom-app.example.com"  # Your production hostname
    
    grafana:
      dashboards:
        enabled: true
        namespace: "monitoring"  # Verify Grafana namespace
        folder: "/Applications"
```

## Verification Steps

### Step 1: Verify OpenTelemetry Operator is Installed

```bash
# Check operator is running
kubectl get pods -n opentelemetry

# Check for OpenTelemetryCollector CRDs
kubectl get crd | grep opentelemetry

# List OpenTelemetryCollector CRs (this creates the actual collector)
kubectl get opentelemetrycollector -n opentelemetry
```

### Step 2: Identify Collector Service Name

```bash
# Get all collector services in opentelemetry namespace
kubectl get svc -n opentelemetry | grep collector

# Get service details to verify port name
kubectl get svc <collector-service-name> -n opentelemetry -o yaml

# Common service names (match CR name exactly):
# - collector (if CR is named 'collector')
# - otelcol (if CR is named 'otelcol')
# - opentelemetry-collector (if CR is named 'opentelemetry-collector')
# Note: Deployment names have "-collector" suffix, but Service names match CR name
```

### Step 3: Verify Service Labels

```bash
# Get service labels (should match OpenTelemetry Operator standards)
kubectl get svc <collector-service-name> -n opentelemetry -o jsonpath='{.metadata.labels}' | jq

# Should see:
# {
#   "app.kubernetes.io/name": "opentelemetry-collector",
#   "app.kubernetes.io/component": "collector",
#   "app.kubernetes.io/managed-by": "opentelemetry-operator"
# }
```

### Step 4: Verify kube-prometheus-stack (Mesosphere Kommander)

```bash
# Check where Prometheus is deployed (kube-prometheus-stack)
kubectl get deployment -A | grep prometheus

# Check Prometheus service name (pattern: <release-name>-kube-prometheus-prometheus)
kubectl get svc -A | grep prometheus | grep -v prometheus-operated

# Common service names:
# - kube-prometheus-stack-prometheus
# - prometheus-kube-prometheus-prometheus
# - prometheus-operated

# Check where Grafana is deployed (part of kube-prometheus-stack)
kubectl get deployment -A | grep grafana

# Check Grafana service name (pattern: <release-name>-grafana)
kubectl get svc -A | grep grafana

# Common service names:
# - kube-prometheus-stack-grafana
# - prometheus-grafana

# Verify namespace (should match kube-prometheus-stack HelmRelease targetNamespace)
kubectl get helmrelease -A | grep prometheus
```

### Step 5: Verify Grafana Loki (Mesosphere Kommander)

```bash
# Check where Loki is deployed (project-grafana-loki)
kubectl get deployment -A | grep loki

# Check Loki service names (project-grafana-loki creates gateway and main service)
kubectl get svc -A | grep loki

# Common service names:
# - project-grafana-loki-gateway (gateway service, port 80)
# - project-grafana-loki (main service, port 3100)
# - loki-gateway
# - loki

# Verify namespace (should match project-grafana-loki HelmRelease targetNamespace)
kubectl get helmrelease -A | grep loki
```

### Step 6: Verify Gateway API CRDs (Mesosphere Kommander)

```bash
# Verify Gateway API CRDs are installed (gateway-api-crds/1.11.1)
kubectl get crd | grep gateway.networking.k8s.io

# Should see CRDs like:
# - gateways.gateway.networking.k8s.io
# - httproutes.gateway.networking.k8s.io
# - referencegrants.gateway.networking.k8s.io
# etc.

# Verify HTTPRoute CRD API version (should be v1 for CRDs 1.11.1)
kubectl get crd httproutes.gateway.networking.k8s.io -o jsonpath='{.spec.versions[*].name}'
# Should include: v1

# Verify Gateway API CRDs HelmRelease
kubectl get helmrelease -A | grep gateway-api
```

### Step 7: Verify Traefik (Mesosphere Kommander)

```bash
# Check where Traefik is deployed
kubectl get deployment -A | grep traefik

# Check Traefik service
kubectl get svc -A | grep traefik

# Common service names:
# - traefik

# Check Gateway API Gateway resource (requires Gateway API CRDs)
kubectl get gateway -A

# Common Gateway names:
# - traefik

# Verify namespace (should match Traefik HelmRelease targetNamespace)
kubectl get helmrelease -A | grep traefik

# Common namespaces:
# - traefik-system
# - traefik
# - ingress
```

### Step 8: Verify Namespaces Summary

```bash
# Summary of common NKP namespaces with Mesosphere Kommander:
kubectl get helmrelease -A | grep -E "opentelemetry|prometheus|loki|traefik|gateway-api"

# Expected HelmReleases:
# - opentelemetry-operator (OpenTelemetry Operator)
# - kube-prometheus-stack (Prometheus, Grafana)
# - project-grafana-loki (Loki)
# - traefik (Traefik + Gateway implementation)
# - gateway-api-crds (Gateway API CRDs - typically installed in cluster scope)

# Expected namespaces:
# - opentelemetry (OpenTelemetry Operator)
# - monitoring (kube-prometheus-stack - Prometheus, Grafana)
# - monitoring (project-grafana-loki - Loki) - OR separate namespace
# - traefik-system (Traefik + Gateway) - OR traefik/ingress namespace
```

### Step 5: Test OTLP Connection

```bash
# Port-forward to collector (if needed for testing)
kubectl port-forward -n opentelemetry svc/<collector-service-name> 4317:4317

# Test connection from app pod (after deployment)
kubectl exec -it <app-pod-name> -n <app-namespace> -- \
  nc -zv collector.opentelemetry.svc.cluster.local 4317
```

## Common Issues and Solutions

### Issue 1: Cannot Connect to Collector

**Symptoms:** App pods show OTLP connection errors

**Solution:**
1. Verify collector service exists: `kubectl get svc -n opentelemetry`
2. Verify service name matches your ConfigMap value
3. Check if OpenTelemetryCollector CR exists: `kubectl get opentelemetrycollector -n opentelemetry`
4. Verify network policies allow traffic

### Issue 2: ServiceMonitor Not Finding Collector

**Symptoms:** Metrics not appearing in Prometheus

**Solution:**
1. Verify ServiceMonitor namespace matches Prometheus Operator namespace
2. Verify selector labels match collector service labels:
   ```bash
   kubectl get svc <collector-service-name> -n opentelemetry -o yaml | grep -A 5 labels
   ```
3. Check ServiceMonitor is created: `kubectl get servicemonitor -n <prometheus-ns>`
4. Verify namespaceSelector matches collector namespace

### Issue 3: Wrong Port Name

**Symptoms:** Prometheus can't scrape metrics

**Solution:**
1. Get actual port names: `kubectl get svc <collector-service-name> -n opentelemetry -o yaml`
2. Update `prometheusPort` in ConfigMap to match actual port name
3. Common port names: `otlp`, `prometheus`, `metrics`

### Issue 4: Namespace Mismatch

**Symptoms:** Resources not found or not working

**Solution:**
1. Verify all namespace references match your NKP cluster:
   - OpenTelemetry Operator: `opentelemetry`
   - Prometheus: `monitoring` (verify)
   - Grafana: `monitoring` (verify)
   - Traefik: `traefik-system` (verify)
2. Update ConfigMap values accordingly

## Chart Compatibility Summary

| Component | Default (values.yaml) | NKP (values-nkp.yaml) | Status |
|-----------|----------------------|----------------------|--------|
| **OTel Collector Endpoint** | `otel-collector.observability.svc.cluster.local:4317` | `collector.opentelemetry.svc.cluster.local:4317` | ⚠️ **NEEDS UPDATE** |
| **OTel Namespace** | `observability` | `opentelemetry` | ⚠️ **NEEDS UPDATE** |
| **ServiceMonitor Labels** | `component: otel-collector` | `app.kubernetes.io/name: opentelemetry-collector` | ⚠️ **NEEDS UPDATE** |
| **ServiceMonitor Namespace** | `observability` | `monitoring` (verify) | ⚠️ **NEEDS UPDATE** |
| **Prometheus Port** | `prometheus` | `otlp` (verify) | ⚠️ **NEEDS VERIFICATION** |
| **Grafana Namespace** | `observability` | `monitoring` (verify) | ⚠️ **NEEDS UPDATE** |
| **Gateway Namespace** | `traefik-system` | `traefik-system` | ✅ Compatible (verify) |

## Recommended Action Plan

1. ✅ **Use `values-nkp.yaml` as base** for your ConfigMap
2. ✅ **Verify service names** in your NKP cluster:
   ```bash
   kubectl get svc -n opentelemetry | grep collector
   ```
3. ✅ **Verify namespaces** for Prometheus, Grafana, Traefik
4. ✅ **Verify port names** on collector service
5. ✅ **Update ConfigMap** with verified values
6. ✅ **Test deployment** in a non-production namespace first
7. ✅ **Verify telemetry flow**: App → OTel Collector → Prometheus/Loki/Tempo

## Related Documentation

- [VALUES_SELECTION.md](../chart/dm-nkp-gitops-custom-app/VALUES_SELECTION.md) - How Helm selects values files
- [DUPLICATE_LOG_COLLECTION.md](./DUPLICATE_LOG_COLLECTION.md) - Handling duplicate logs with Logging Operator
- [OpenTelemetry Operator Documentation](https://opentelemetry.io/docs/kubernetes/operator/) - Official operator docs

## References

- [App HelmRelease](https://github.com/deepak-muley/dm-nkp-gitops-app-catalog/blob/main/applications/dm-nkp-gitops-custom-app/0.1.0/helmrelease/helmrelease.yaml)
- [OpenTelemetry Operator HelmRelease](https://github.com/nutanix-cloud-native/nkp-nutanix-product-catalog/blob/release-2.x/applications/opentelemetry-operator/0.93.0/helmrelease/opentelemetry.yaml)
