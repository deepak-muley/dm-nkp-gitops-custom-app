# Helm Values File Selection - Quick Reference

## How Helm Selects Values Files

**⚠️ IMPORTANT: Helm does NOT automatically detect which values file to use!**

### Default Behavior

**`values.yaml` is ALWAYS the default** - Helm uses this file automatically if no `-f` flag is specified.

```bash
# Uses values.yaml (default)
helm install my-app ./chart/dm-nkp-gitops-custom-app

# Also uses values.yaml (no -f flag = default)
helm install my-app ./chart/dm-nkp-gitops-custom-app --namespace production
```

### Explicit Values File Selection

**You must explicitly specify other values files using the `-f` flag:**

```bash
# Uses values-production.yaml (explicitly specified)
helm install my-app ./chart/dm-nkp-gitops-custom-app -f values-production.yaml

# Uses values-local-testing.yaml (explicitly specified)
helm install my-app ./chart/dm-nkp-gitops-custom-app -f values-local-testing.yaml
```

### Combining Multiple Values Files

**You can combine multiple values files** (later files override earlier ones):

```bash
# Uses values.yaml as base, then overrides with values-production.yaml
helm install my-app ./chart/dm-nkp-gitops-custom-app \
  -f values.yaml \
  -f values-production.yaml

# Values are merged, with values-production.yaml taking precedence
```

## Values Files in This Chart

| Values File | Purpose | Auto-Used? | When to Use |
|------------|---------|------------|-------------|
| `values.yaml` | **Default values** (production-ready) | ✅ Yes (default) | Production deployments with standard platform service locations |
| `values-production.yaml` | Production-specific overrides (example) | ❌ No (must specify `-f`) | Production with custom settings (autoscaling, more replicas, etc.) |
| `values-local-testing.yaml` | Local testing with observability-stack | ❌ No (must specify `-f`) | Local testing when deploying observability-stack chart first |

## Production Deployment Examples

### Option 1: Use Default Values (Simplest)

**✅ Recommended if platform services are in standard locations:**

```bash
# Just install with default values.yaml (no -f flag needed)
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  --create-namespace
```

**Works if platform services are in (NKP standard locations):**
- OpenTelemetry Operator: `opentelemetry` namespace (collector-collector service)
- Traefik + Gateway API: `traefik-system` namespace
- kube-prometheus-stack: `monitoring` namespace (Prometheus, Grafana)
- project-grafana-loki: `monitoring` namespace (Loki)

### Option 2: Use Production Values File

**If you need production-specific settings** (autoscaling, more replicas, different hostnames):

```bash
# Explicitly specify values-production.yaml with -f flag
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  -f values-production.yaml \
  --set gateway.hostnames[0]=dm-nkp-gitops-custom-app.example.com
```

### Option 3: Override Specific Values

**If platform services are in different locations:**

```bash
# Override specific values using --set flags
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  --set opentelemetry.collector.endpoint=collector-collector.opentelemetry.svc.cluster.local:4317 \
  --set gateway.parentRef.namespace=my-traefik-ns \
  --set monitoring.serviceMonitor.namespace=my-prometheus-ns
```

### Option 4: Custom Values File

**Create your own values file:**

```yaml
# my-production-values.yaml
opentelemetry:
  collector:
    endpoint: "collector-collector.opentelemetry.svc.cluster.local:4317"

gateway:
  parentRef:
    namespace: "my-traefik-ns"

monitoring:
  serviceMonitor:
    namespace: "my-prometheus-ns"
```

```bash
# Use your custom values file
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  -f my-production-values.yaml
```

## What Gets Installed

**Regardless of which values file you use, the chart will deploy:**

1. ✅ **Application Deployment** - Your app pods
2. ✅ **Service** - Kubernetes Service for the app
3. ✅ **HTTPRoute** (if `gateway.enabled=true`) - Routes traffic via Traefik Gateway
4. ✅ **ServiceMonitor** (if `monitoring.serviceMonitor.enabled=true`) - Configures Prometheus scraping
5. ✅ **Grafana Dashboards** (if `grafana.dashboards.enabled=true`) - Application dashboards
6. ✅ **Grafana Datasources** (if `grafana.datasources.enabled=true`) - Optional datasources

**All of these reference pre-deployed platform services** (OTel Collector, Traefik Gateway, Prometheus, Grafana).

## Common Mistakes

### ❌ Mistake 1: Assuming values-production.yaml is auto-used

```bash
# This uses values.yaml (default), NOT values-production.yaml!
helm install my-app ./chart/dm-nkp-gitops-custom-app --namespace production
```

**Correct:**
```bash
# Must explicitly specify with -f flag
helm install my-app ./chart/dm-nkp-gitops-custom-app -f values-production.yaml
```

### ❌ Mistake 2: Thinking Helm auto-detects environment

Helm does **NOT** detect "production" vs "local" automatically. There's no magic!

**You must explicitly tell Helm which values file to use.**

### ❌ Mistake 3: Confusing values files

- `values.yaml` = Default (used automatically)
- `values-production.yaml` = Example production overrides (must specify `-f`)
- `values-local-testing.yaml` = Local testing (must specify `-f`)

## Verification

**To see what values will be used:**

```bash
# Render templates with default values.yaml
helm template my-app ./chart/dm-nkp-gitops-custom-app

# Render templates with values-production.yaml
helm template my-app ./chart/dm-nkp-gitops-custom-app -f values-production.yaml

# See all values that will be used (including defaults)
helm template my-app ./chart/dm-nkp-gitops-custom-app --debug
```

## Summary

| Question | Answer |
|----------|--------|
| Which values file is used by default? | `values.yaml` |
| Do I need to specify `-f` for `values.yaml`? | ❌ No - it's the default |
| Do I need to specify `-f` for `values-production.yaml`? | ✅ Yes - must specify with `-f values-production.yaml` |
| Can I use default values.yaml in production? | ✅ Yes - it's production-ready by default |
| Does Helm auto-detect environment? | ❌ No - you must explicitly specify values files |
| How do I know what values are used? | Use `helm template ... --debug` to see all values |

## Related Documentation

- [Chart README.md](./README.md) - Complete chart documentation
- [DUPLICATE_LOG_COLLECTION.md](../../docs/DUPLICATE_LOG_COLLECTION.md) - Handling duplicate logs with Logging Operator
