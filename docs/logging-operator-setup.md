# Logging Operator Setup for Local Testing

## Overview

The Logging Operator is installed for local testing to capture **stdout/stderr logs** from all pods. This complements the OTLP-based log collection.

**Note**: NKP platform will have Logging Operator pre-installed, so this setup ensures local testing matches production behavior.

## Architecture

```
Application Pods
├─→ OTLP logs → OTel Collector (deployment) → Loki ✅
└─→ stdout/stderr logs → Logging Operator → Fluent Bit/D (DaemonSet) → Loki ✅
```

## Installation

### Automatic Installation (via e2e-demo-otel.sh)

The `scripts/e2e-demo-otel.sh` script automatically installs:

1. **Logging Operator** (Helm chart: `kube-logging/logging-operator`)
2. **Logging Resource** (defines Fluent Bit/D configuration)
3. **Output Resource** (sends logs to Loki)
4. **Flow Resource** (defines what logs to collect)

### Manual Installation

```bash
# Add Helm repository
helm repo add kube-logging https://kube-logging.github.io/helm-charts
helm repo update

# Install Logging Operator
helm upgrade --install logging-operator kube-logging/logging-operator \
  --namespace logging \
  --create-namespace \
  --wait --timeout=5m
```

## Configuration

### Logging Resource

Defines the logging system (Fluent Bit/D):

```yaml
apiVersion: logging.banzaicloud.io/v1beta1
kind: Logging
metadata:
  name: default
  namespace: logging
spec:
  fluentd:
    image:
      repository: fluent/fluentd
      tag: v1.16-debian-1
  fluentbit:
    image:
      repository: fluent/fluent-bit
      tag: 2.2.0
  controlNamespace: logging
```

### Output Resource

Defines where logs go (Loki):

```yaml
apiVersion: logging.banzaicloud.io/v1beta1
kind: Output
metadata:
  name: loki
  namespace: logging
spec:
  loki:
    url: http://loki-loki-distributed-gateway.observability.svc.cluster.local:80/loki/api/v1/push
    configure_kubernetes_labels: true
    buffer:
      type: file
      path: /buffers/loki
      flush_interval: 5s
      flush_mode: immediate
      retry_type: exponential_backoff
      retry_wait: 1s
      retry_max_interval: 60s
      retry_timeout: 60m
      chunk_limit_size: 1M
      total_limit_size: 500M
      overflow_action: block
```

### Flow Resource

Defines what logs to collect:

```yaml
apiVersion: logging.banzaicloud.io/v1beta1
kind: Flow
metadata:
  name: default
  namespace: logging
spec:
  # Match all pods (stdout/stderr logs)
  match:
    - select: {}  # Empty select matches all pods
  localOutputRefs:
    - loki
  filters:
    - parser:
        remove_key_name_field: true
        reserve_data: true
        parse:
          type: json
          time_key: time
          time_format: "%Y-%m-%dT%H:%M:%S.%NZ"
```

## Filtering Logs

### Collect Only Specific Pods

To collect logs only from your application:

```yaml
spec:
  match:
    - select:
        labels:
          app.kubernetes.io/name: dm-nkp-gitops-custom-app
```

### Collect Only Specific Namespace

```yaml
spec:
  match:
    - select:
        namespaces:
          - default
```

### Exclude System Pods

```yaml
spec:
  match:
    - select: {}  # All pods
  exclude:
    - select:
        namespaces:
          - kube-system
          - kube-public
          - kube-node-lease
```

## Verification

### Check Logging Operator Status

```bash
# Check operator pod
kubectl get pods -n logging -l app.kubernetes.io/name=logging-operator

# Check Fluent Bit/D pods (DaemonSet)
kubectl get pods -n logging -l app.kubernetes.io/name=fluentbit
# or
kubectl get pods -n logging -l app.kubernetes.io/name=fluentd
```

### Check Logging Resources

```bash
# Check Logging resource
kubectl get logging -n logging

# Check Output resource
kubectl get output -n logging

# Check Flow resource
kubectl get flow -n logging
```

### Check Logs in Loki

```bash
# Port forward to Loki
kubectl port-forward -n observability svc/loki-loki-distributed-gateway 3100:80

# Query logs (stdout/stderr logs will have Kubernetes labels)
curl -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={app_kubernetes_io_name="dm-nkp-gitops-custom-app"}' \
  --data-urlencode "start=$(date -u -v-15M +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000"
```

## Log Labels

### OTLP Logs

- Label: `service_name="dm-nkp-gitops-custom-app"`
- Source: Application sends via OTLP
- Collector: OTel Collector (deployment mode)

### stdout/stderr Logs (via Logging Operator)

- Labels: `app_kubernetes_io_name="dm-nkp-gitops-custom-app"`, `namespace="default"`, etc.
- Source: Pod stdout/stderr
- Collector: Fluent Bit/D (DaemonSet via Logging Operator)

## Dashboard Queries

### For OTLP Logs

```logql
{service_name="dm-nkp-gitops-custom-app"}
```

### For stdout/stderr Logs

```logql
{app_kubernetes_io_name="dm-nkp-gitops-custom-app"}
```

### For Both

```logql
{app_kubernetes_io_name="dm-nkp-gitops-custom-app"} or {service_name="dm-nkp-gitops-custom-app"}
```

## NKP Platform Compatibility

### Production Setup

NKP platform will have:

- ✅ Logging Operator pre-installed
- ✅ Fluent Bit/D DaemonSet running
- ✅ Output configured to send to Loki
- ✅ Flow configured (may collect all pods or filtered)

### Local Testing Setup

The `e2e-demo-otel.sh` script installs:

- ✅ Logging Operator (matches NKP platform)
- ✅ Same configuration structure
- ✅ Same Loki endpoint format

This ensures **local testing matches production behavior**.

## Troubleshooting

### Logging Operator Not Starting

```bash
# Check operator logs
kubectl logs -n logging -l app.kubernetes.io/name=logging-operator

# Check CRDs
kubectl get crd | grep logging.banzaicloud.io
```

### Fluent Bit/D Not Collecting Logs

```bash
# Check Fluent Bit/D pods
kubectl get pods -n logging -l app.kubernetes.io/name=fluentbit

# Check Fluent Bit/D logs
kubectl logs -n logging -l app.kubernetes.io/name=fluentbit --tail=50

# Check Flow resource
kubectl describe flow default -n logging
```

### Logs Not Reaching Loki

```bash
# Check Output resource
kubectl describe output loki -n logging

# Verify Loki endpoint is correct
kubectl get svc -n observability | grep loki

# Test Loki endpoint
kubectl port-forward -n observability svc/loki-loki-distributed-gateway 3100:80
curl http://localhost:3100/ready
```

## Summary

- ✅ **Logging Operator installed** for local testing
- ✅ **Collects stdout/stderr logs** from all pods
- ✅ **Sends to Loki** (same endpoint as OTLP logs)
- ✅ **OTLP logs** still work (OTel Collector in deployment mode)
- ✅ **NKP platform compatible** (same setup as production)

**Result**: Both OTLP and stdout/stderr logs are captured and sent to Loki! 🎉
