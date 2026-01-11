# dm-nkp-gitops-custom-app Helm Chart

Helm chart for deploying dm-nkp-gitops-custom-app with OpenTelemetry observability.

## Architecture

### Production Deployment (Platform Services Pre-deployed - NKP Compatible)

```
Platform Services (Pre-deployed by platform team via Mesosphere Kommander)
├── Traefik + Gateway API (namespace: traefik-system)
│   └── Gateway API CRDs: gateway-api-crds/1.11.1
├── OpenTelemetry Operator (namespace: opentelemetry)
│   └── OpenTelemetryCollector CR → collector-collector service
├── kube-prometheus-stack (namespace: monitoring)
│   ├── Prometheus Operator
│   ├── Prometheus
│   └── Grafana
├── project-grafana-loki (namespace: monitoring)
│   └── Loki (project-grafana-loki-gateway service)
└── Grafana Tempo (namespace: monitoring, if deployed)

Application Chart (This Chart)
├── Application Deployment
├── HTTPRoute CR → References pre-deployed Traefik Gateway
├── ServiceMonitor CR → References pre-deployed OpenTelemetry Operator collector
└── Grafana Dashboard ConfigMaps → References pre-deployed kube-prometheus-stack Grafana
```

### Local Testing Deployment

```
OpenTelemetry Operator (LOCAL TESTING)
├── Deploys: OpenTelemetry Operator
└── Namespace: opentelemetry
    └── OpenTelemetryCollector CR → Creates collector service

kube-prometheus-stack (LOCAL TESTING)
├── Deploys: Prometheus Operator, Prometheus, Grafana
└── Namespace: monitoring

Application Chart (This Chart)
├── Application Deployment
├── HTTPRoute CR → Optional (if Traefik + Gateway API is installed)
├── ServiceMonitor CR → References OpenTelemetry Operator collector
└── Grafana Dashboard ConfigMaps → References kube-prometheus-stack Grafana
```

**Note**: Local testing now uses the same setup as NKP production (OpenTelemetry Operator + kube-prometheus-stack), making it easier to validate compatibility.

## Quick Start

### Production Deployment (Simplest - Uses Default Values)

**✅ If your platform services are in standard NKP locations** (default `values.yaml` is NKP-compatible):

```bash
# Platform services are pre-deployed in standard NKP locations:
# - OpenTelemetry Operator: opentelemetry namespace (collector-collector service)
# - Traefik + Gateway API: traefik-system namespace
# - kube-prometheus-stack: monitoring namespace (Prometheus, Grafana)
# - project-grafana-loki: monitoring namespace (Loki)

# Deploy with default values.yaml (NKP-compatible by default)
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  --create-namespace
```

**That's it!** The default `values.yaml` is configured for NKP production. Your app will:
- ✅ Connect to OpenTelemetry Operator collector at `collector.opentelemetry.svc.cluster.local:4317`
- ✅ Deploy HTTPRoute referencing Traefik Gateway
- ✅ Deploy ServiceMonitor for Prometheus scraping (with OpenTelemetry Operator labels)
- ✅ Deploy Grafana dashboards to monitoring namespace

### Production Deployment (With Custom Values File)

**If you need production-specific settings** (autoscaling, more replicas, different hostnames, etc.):

```bash
# Use values-production.yaml (explicitly specified with -f flag)
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  -f values-production.yaml \
  --set gateway.hostnames[0]=dm-nkp-gitops-custom-app.example.com
```

**Note**: `values-production.yaml` is just an **example** - it won't be used automatically. You must specify it with `-f values-production.yaml`.

### Production Deployment (With Custom Overrides)

**If your platform services are in different locations**:

```bash
# Override specific values using --set flags
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  --set opentelemetry.collector.endpoint=otel-collector.my-platform.svc.cluster.local:4317 \
  --set gateway.parentRef.namespace=my-traefik-ns \
  --set monitoring.serviceMonitor.namespace=my-prometheus-ns \
  --set grafana.dashboards.namespace=my-grafana-ns

# Or create a custom values file
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  -f my-custom-values.yaml
```

### Local Testing

```bash
# Step 1: Deploy OpenTelemetry Operator (for local testing)
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml

# OR via Helm:
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace opentelemetry \
  --create-namespace \
  --wait

# Step 2: Create OpenTelemetryCollector CR (default collector named 'collector')
kubectl apply -f - <<EOF
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: collector
  namespace: opentelemetry
spec:
  mode: deployment
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
    exporters:
      prometheus:
        endpoint: 0.0.0.0:8889
      logging:
    service:
      pipelines:
        metrics:
          receivers: [otlp]
          exporters: [prometheus]
EOF

# Step 3: Deploy kube-prometheus-stack (for Prometheus/Grafana)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --wait

# Step 4: Deploy application with local testing values
helm upgrade --install dm-nkp-gitops-custom-app . \
  --namespace default \
  -f values-local-testing.yaml
```

## Configuration

### OpenTelemetry Configuration (NKP Compatible - OpenTelemetry Operator)

```yaml
opentelemetry:
  enabled: true
  collector:
    # NKP OpenTelemetry Operator collector endpoint
    # Service name matches OpenTelemetryCollector CR name exactly (not Deployment name)
    endpoint: "collector.opentelemetry.svc.cluster.local:4317"
  env:
    - name: OTEL_EXPORTER_OTLP_ENDPOINT
      value: "collector-collector.opentelemetry.svc.cluster.local:4317"
```

### Gateway API Configuration (Traefik + Gateway API)

The chart deploys an HTTPRoute that references the pre-deployed Traefik Gateway:

```yaml
gateway:
  enabled: true  # Enable HTTPRoute deployment (assumes Gateway API is pre-deployed)
  parentRef:
    name: "traefik"  # Name of the Gateway resource (pre-deployed by platform team)
    namespace: "traefik-system"  # Namespace where Gateway is deployed
  hostnames:
    - "dm-nkp-gitops-custom-app.local"  # Update to your production hostname
```

**Note**: In production, Traefik with Gateway API support is pre-deployed by the platform team. This chart deploys only the HTTPRoute resource that references the pre-deployed Gateway.

### ServiceMonitor Configuration

The chart deploys a ServiceMonitor that configures Prometheus to scrape metrics from the OpenTelemetry Operator collector's Prometheus endpoint:

```yaml
monitoring:
  serviceMonitor:
    enabled: true
    namespace: "monitoring"  # NKP: Where kube-prometheus-stack is deployed
    otelCollector:
      namespace: "opentelemetry"  # NKP: Where OpenTelemetry Operator is deployed
      selectorLabels:
        app.kubernetes.io/name: opentelemetry-collector  # NKP: OpenTelemetry Operator standard labels
        app.kubernetes.io/component: collector
```

### Grafana Dashboard and Datasource Configuration

The chart deploys Grafana dashboards and datasources as ConfigMaps:

```yaml
grafana:
  dashboards:
    enabled: true
    namespace: "monitoring"  # NKP: Where kube-prometheus-stack Grafana is deployed
    folder: "/"  # Grafana folder for dashboards
  
  datasources:
    enabled: false  # Platform team should configure datasources in production
    namespace: "monitoring"  # NKP: Same as Grafana namespace
    prometheus:
      enabled: true
      url: "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
    loki:
      enabled: true
      url: "http://project-grafana-loki-gateway.monitoring.svc.cluster.local:80"
    tempo:
      enabled: true
      url: "http://tempo.monitoring.svc.cluster.local:3200"
```

**Automatic Discovery:**
- **Dashboards**: Automatically discovered by Grafana with label `grafana_dashboard=1` (works with kube-prometheus-stack's sidecar)
- **Datasources**: For kube-prometheus-stack, datasources are typically configured via Helm values (`grafana.additionalDataSources`). The ConfigMap provided here can be used as a reference or for manual provisioning if Grafana has datasource sidecar enabled.

## App-Specific Custom Resources Deployed

1. **HTTPRoute** (`templates/httproute.yaml`) - **NEW!**
   - Routes traffic to application via Traefik Gateway (Gateway API)
   - References pre-deployed Traefik Gateway (pre-deployed by platform team)
   - Deployed to application namespace
   - **Production**: Automatically deployed if `gateway.enabled=true` (default in production)
   - **Local Testing**: Auto-enabled if Gateway API is detected, otherwise disabled

2. **ServiceMonitor** (`templates/servicemonitor-otel.yaml`)
   - Configures Prometheus to scrape OpenTelemetry Operator collector's metrics endpoint
   - References pre-deployed OpenTelemetry Operator collector service (NKP compatible)
   - Uses OpenTelemetry Operator standard labels (`app.kubernetes.io/name: opentelemetry-collector`)
   - Deployed to kube-prometheus-stack namespace (monitoring)

3. **Grafana Dashboard ConfigMaps** (`templates/grafana-dashboards.yaml`)
   - Metrics Dashboard (Prometheus data source)
   - Logs Dashboard (Loki data source - NKP: project-grafana-loki)
   - Traces Dashboard (Tempo data source)
   - Deployed to kube-prometheus-stack Grafana namespace (monitoring) with label `grafana_dashboard=1`
   - Automatically discovered by Grafana (kube-prometheus-stack sidecar)

4. **Grafana Datasource ConfigMap** (`templates/grafana-datasources.yaml`)
   - Prometheus datasource configuration
   - Loki datasource configuration
   - Tempo datasource configuration
   - Deployed to Grafana namespace with label `grafana_datasource=1`
   - Note: For kube-prometheus-stack, datasources are typically configured via Helm values, but this ConfigMap can be used if Grafana has datasource provisioning enabled

## Platform Service References

The chart references pre-deployed platform services via configurable values. Update these for your platform:

### Traefik Gateway (Gateway API - NKP Compatible)
- **Gateway API CRDs**: Pre-deployed via Mesosphere Kommander (gateway-api-crds/1.11.1)
- **Gateway resource**: Configured via `gateway.parentRef.name` and `gateway.parentRef.namespace`
- **Default**: References `traefik` Gateway in `traefik-system` namespace
- **Production**: Traefik with Gateway API support is pre-deployed by platform team (traefik/37.1.2)
- **Local Testing**: Install Gateway API CRDs: `kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml`

### OpenTelemetry Operator (NKP Compatible)
- Operator namespace: `opentelemetry`
- Collector service: `<OpenTelemetryCollector-CR-name>.opentelemetry.svc.cluster.local:4317` (Service name matches CR name)
- Default service: `collector.opentelemetry.svc.cluster.local:4317` (if CR is named 'collector')
- Note: Service name matches CR name; Deployment name would be `collector-collector` (with suffix)
- Service labels: OpenTelemetry Operator uses standard labels (`app.kubernetes.io/name: opentelemetry-collector`)

### Prometheus Operator (kube-prometheus-stack - NKP Compatible)
- Namespace: `monitoring` (default, configured via `monitoring.serviceMonitor.namespace`)
- Service name pattern: `<release-name>-kube-prometheus-prometheus`
- Default service: `kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090`
- Discovers ServiceMonitors automatically

### Grafana (kube-prometheus-stack - NKP Compatible)
- Namespace: `monitoring` (default, configured via `grafana.dashboards.namespace` or `grafana.datasources.namespace`)
- Service name pattern: `<release-name>-grafana`
- Default service: `kube-prometheus-stack-grafana.monitoring.svc.cluster.local:80`
- **Dashboards**: Automatically discovers dashboards via ConfigMap label `grafana_dashboard=1` (kube-prometheus-stack sidecar enabled by default)
- **Datasources**: For kube-prometheus-stack, typically configured via `grafana.additionalDataSources` Helm value. The ConfigMap provided here serves as a reference or can be used if Grafana has datasource provisioning enabled (`sidecar.datasources.enabled=true`)

### Grafana Loki (project-grafana-loki - NKP Compatible)
- Namespace: `monitoring` (default, same as kube-prometheus-stack)
- Service name pattern: `<release-name>-gateway` (gateway service, port 80) or `<release-name>` (main service, port 3100)
- Default gateway: `project-grafana-loki-gateway.monitoring.svc.cluster.local:80`
- Default main: `project-grafana-loki.monitoring.svc.cluster.local:3100`

## Values Files

> 📖 **Quick Reference**: See [VALUES_SELECTION.md](./VALUES_SELECTION.md) for a complete guide on how Helm selects values files.

### How Helm Selects Values Files

**Important**: Helm does **NOT** automatically detect which values file to use. You must explicitly specify values files using the `-f` flag.

| Values File | When to Use | How to Use |
|------------|-------------|------------|
| `values.yaml` | **Default** - Used automatically if no `-f` flag is specified | `helm install ...` (no `-f` flag) |
| `values-production.yaml` | Production-specific overrides (example) | `helm install ... -f values-production.yaml` |
| `values-local-testing.yaml` | Local testing with observability-stack chart | `helm install ... -f values-local-testing.yaml` |

**Example:**
```bash
# Uses values.yaml (default)
helm install my-app ./chart/dm-nkp-gitops-custom-app

# Uses values-production.yaml (explicit)
helm install my-app ./chart/dm-nkp-gitops-custom-app -f values-production.yaml

# Uses values-local-testing.yaml (explicit)
helm install my-app ./chart/dm-nkp-gitops-custom-app -f values-local-testing.yaml

# Combine multiple values files (later files override earlier ones)
helm install my-app ./chart/dm-nkp-gitops-custom-app -f values.yaml -f values-production.yaml
```

### Default Values (`values.yaml`)

**Production-Ready by Default (NKP Compatible)**: The default `values.yaml` is configured to work out-of-the-box in production environments (NKP with Mesosphere Kommander), assuming platform services are pre-deployed in the standard locations:

- ✅ OpenTelemetry Operator: `collector.opentelemetry.svc.cluster.local:4317` (OpenTelemetry Operator)
- ✅ Gateway API: References `traefik` Gateway in `traefik-system` namespace (Traefik + Gateway API CRDs)
- ✅ ServiceMonitor: Deploys to `monitoring` namespace (where kube-prometheus-stack is)
- ✅ Grafana Dashboards: Deploys to `monitoring` namespace (where kube-prometheus-stack Grafana is)

**If your platform services are in different namespaces/endpoints**, override them using:
- `--set` flags
- Custom values file with `-f`
- Or modify `values-production.yaml` to match your platform

### Values File Details

- **`values.yaml`** - Default values (NKP-compatible production-ready defaults, uses OpenTelemetry Operator)
- **`values-production.yaml`** - Production deployment with NKP-compatible settings (autoscaling enabled, more replicas, etc.)
- **`values-nkp.yaml`** - Nutanix Kubernetes Platform (NKP) with FluxCD and OpenTelemetry Operator configuration (reference for NKP-specific overrides)
- **`values-local-testing.yaml`** - Local testing with OpenTelemetry Operator and kube-prometheus-stack (uses local image, same setup as NKP)

### NKP Deployment (FluxCD + OpenTelemetry Operator)

**For NKP deployments**, use `values-nkp.yaml` as a base for your ConfigMap. See [NKP_DEPLOYMENT.md](../../docs/NKP_DEPLOYMENT.md) for:
- OpenTelemetry Operator vs Direct Collector differences
- Required configuration changes
- Verification steps
- Troubleshooting guide

## Grafana Dashboards and Datasources

### Dashboards

Three dashboards are automatically deployed:

1. **Metrics Dashboard** - HTTP metrics, request rates, durations, business metrics (uses Prometheus)
2. **Logs Dashboard** - Application logs, log levels, error logs (uses Loki)
3. **Traces Dashboard** - Distributed traces, trace rates, duration distributions (uses Tempo)

Dashboards are deployed as ConfigMaps with label `grafana_dashboard=1` and are **automatically discovered** by Grafana when using kube-prometheus-stack (sidecar enabled by default).

### Datasources

The chart can optionally deploy datasource ConfigMaps with label `grafana_datasource=1`:

- **Prometheus** - For metrics queries (UID: `prometheus`)
- **Loki** - For log queries (UID: `loki`)
- **Tempo** - For trace queries (UID: `tempo`)

**Automatic Discovery:**
- **For kube-prometheus-stack**: Datasources are typically configured via Helm values (`grafana.additionalDataSources`). To use the ConfigMap approach, ensure Grafana has `sidecar.datasources.enabled=true` in the kube-prometheus-stack values.
- **For standalone Grafana**: The ConfigMaps can be mounted into Grafana's provisioning directory (`/etc/grafana/provisioning/datasources`).

**Local Testing**: Datasources are enabled in `values-local-testing.yaml` and work automatically if using the observability-stack chart.

**Production**: Datasources are disabled by default in `values-production.yaml` (assuming platform team configures them). Enable if needed.

## Beginner's Guide

New to Grafana? See **[Grafana Beginner's Guide](../../docs/GRAFANA_BEGINNER_GUIDE.md)** for a complete explanation of:
- What are dashboards, datasources, and providers
- How auto-discovery works
- Step-by-step setup instructions
- Troubleshooting tips

## Troubleshooting

See `docs/GRAFANA_DASHBOARDS_SETUP.md` for detailed troubleshooting guide.

## Important Notes

### Values File Selection

**⚠️ Helm does NOT automatically select values files!**

- **Default**: `values.yaml` is used automatically if no `-f` flag is specified
- **Production**: `values-production.yaml` must be explicitly specified: `helm install ... -f values-production.yaml`
- **Local Testing**: `values-local-testing.yaml` must be explicitly specified: `helm install ... -f values-local-testing.yaml`

**Example:**
```bash
# Uses default values.yaml
helm install my-app ./chart/dm-nkp-gitops-custom-app

# Uses values-production.yaml (must specify -f flag)
helm install my-app ./chart/dm-nkp-gitops-custom-app -f values-production.yaml
```

### Production-Ready Defaults

**✅ The default `values.yaml` is production-ready by default!**

The default values assume platform services are pre-deployed in standard locations:
- OTel Collector: `observability` namespace
- Traefik + Gateway API: `traefik-system` namespace
- Prometheus/Grafana: `observability` namespace

**If you install this chart with just `helm install ...` (no `-f` flag), it will work out-of-the-box in production, assuming:**
1. Platform services are pre-deployed in the standard locations above
2. Gateway API CRDs are installed (for HTTPRoute)
3. Prometheus Operator is installed (for ServiceMonitor)

**If your platform services are in different locations**, override using `--set` flags or a custom values file. See `values-nkp.yaml` as a reference for NKP-specific configurations.

### Log Collection & Duplicates

**Note**: This app chart does **NOT** control whether OTel Collector collects logs or not. The OTel Collector's log collection is configured by the **platform team** when they deploy the OTel Collector.

- **This app chart**: Only sends telemetry (metrics, logs, traces) to OTel Collector via OTLP
- **OTel Collector configuration**: Handled by platform team (whether it collects logs or not)

**If duplicate logs are a concern** (OTel Collector + Logging Operator both collecting):
- Platform team should configure OTel Collector to disable log collection if Logging Operator is present
- Or platform team should configure Logging Operator to exclude your namespace
- See [docs/DUPLICATE_LOG_COLLECTION.md](../../docs/DUPLICATE_LOG_COLLECTION.md) for details

### Platform Services

- **Production**: All observability services are pre-deployed by the platform team via Mesosphere Kommander Applications
- **App-Specific CRs**: This chart deploys only app-specific Custom Resources (HTTPRoute, ServiceMonitor, Grafana dashboards) that reference pre-deployed services
- **Local Testing**: Uses OpenTelemetry Operator + kube-prometheus-stack (same setup as NKP production for better compatibility testing)

**Platform Services from Mesosphere Kommander:**
- **OpenTelemetry Operator**: Deploys OpenTelemetry Collector via OpenTelemetryCollector CRs (opentelemetry namespace)
- **kube-prometheus-stack**: Deploys Prometheus Operator, Prometheus, Grafana (monitoring namespace)
- **project-grafana-loki**: Deploys Grafana Loki (monitoring namespace)
- **Traefik + Gateway API**: Deploys Traefik with Gateway API support (traefik-system namespace)
- **gateway-api-crds**: Deploys Gateway API CRDs v1.11.1 (cluster-scoped)
