# Grafana Dashboards - Beginner's Guide

## What You Need: The 3 Main Pieces

To see your application's metrics, logs, and traces in Grafana, you need **3 things working together**:

1. **Data Sources** - Where your data comes from (Prometheus, Loki, Tempo)
2. **Dashboards** - Visual panels that display your data (charts, graphs, tables)
3. **Dashboard Provider** - The mechanism that tells Grafana "here are the dashboards to load"

Think of it like this:
- **Data Source** = The database (Prometheus stores metrics, Loki stores logs, Tempo stores traces)
- **Dashboard** = The report template (defines which charts to show)
- **Provider** = The librarian (tells Grafana where to find dashboard templates)

---

## 1. Data Sources Explained

**What is it?** A data source tells Grafana how to connect to where your data is stored.

**Types of Data Sources:**
- **Prometheus** - Stores metrics (e.g., "how many HTTP requests per second?")
- **Loki** - Stores logs (e.g., "show me all error logs from my app")
- **Tempo** - Stores traces (e.g., "show me the trace of request #12345")

**How are they configured?**

In Kubernetes, data sources can be configured in two ways:

### Option A: Via Helm Values (Recommended for kube-prometheus-stack)
```yaml
# When installing Grafana via kube-prometheus-stack Helm chart
grafana:
  additionalDataSources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server:9090
```

### Option B: Via ConfigMap (What our chart does)
```yaml
# Our chart creates a ConfigMap with datasources.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-app-datasources
  labels:
    grafana_datasource: "1"  # This label tells Grafana sidecar to load it
data:
  datasources.yaml: |
    datasources:
      - name: Prometheus
        url: http://prometheus-server:9090
```

**How does Grafana find them?**

- **kube-prometheus-stack** (most common): Has a "sidecar" container that watches for ConfigMaps with label `grafana_datasource=1` and automatically loads them
- **Standalone Grafana**: You mount the ConfigMap into `/etc/grafana/provisioning/datasources/`

---

## 2. Dashboards Explained

**What is it?** A dashboard is a JSON file that defines:
- Which data source to query (Prometheus, Loki, or Tempo)
- What to query (e.g., `rate(http_requests_total[5m])`)
- How to display it (line chart, bar chart, table, etc.)

**Example Dashboard Structure:**
```json
{
  "title": "My App Metrics",
  "panels": [
    {
      "title": "Request Rate",
      "datasource": "Prometheus",  // <-- Uses the data source we configured
      "targets": [{
        "expr": "rate(http_requests_total[5m])"  // <-- PromQL query
      }]
    }
  ]
}
```

**Where are dashboards stored?**

In Kubernetes, dashboards are stored as ConfigMaps:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-app-dashboard-metrics
  labels:
    grafana_dashboard: "1"  # <-- This label is KEY for auto-discovery
  annotations:
    grafana-folder: "/"  # <-- Which folder in Grafana UI
data:
  dashboard-metrics.json: |
    {
      "title": "My Metrics Dashboard",
      "panels": [...]
    }
```

---

## 3. Dashboard Provider Explained

**What is it?** The provider is a configuration that tells Grafana:
- "Look for dashboards in these ConfigMaps"
- "Organize them in this folder"

**Provider ConfigMap Example:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: dashboard-provider
data:
  dashboards.yaml: |
    providers:
    - name: 'My App Dashboards'
      folder: '/'           # <-- Folder name in Grafana UI
      type: file
      options:
        path: /var/lib/grafana/dashboards/my-app
```

**Do you always need a provider?**

**For kube-prometheus-stack: NO!** 
- kube-prometheus-stack has dashboard auto-discovery **enabled by default**
- It watches for ConfigMaps with label `grafana_dashboard=1`
- The provider ConfigMap is **optional** (only needed for custom folder organization)

**For standalone Grafana: YES**
- You need to mount the provider ConfigMap into `/etc/grafana/provisioning/dashboards/`

---

## 4. How Auto-Discovery Works

### kube-prometheus-stack (Most Common Setup)

**The Magic Sidecar:**

kube-prometheus-stack deploys Grafana with a special "sidecar" container that:
1. Watches for ConfigMaps with label `grafana_dashboard=1`
2. Reads the dashboard JSON from the ConfigMap
3. Automatically imports it into Grafana
4. Refreshes if the ConfigMap changes

**Visual Flow:**
```
Your Helm Chart
    ↓ (creates ConfigMap with label grafana_dashboard=1)
ConfigMap: dashboard-metrics.json
    ↓ (sidecar watches and detects)
Grafana Sidecar Container
    ↓ (imports dashboard)
Grafana UI → Shows your dashboard!
```

**What labels/annotations matter?**

| Label/Annotation | Purpose | Example |
|-----------------|---------|---------|
| `grafana_dashboard=1` | **REQUIRED** - Tells sidecar to load this dashboard | Always needed |
| `grafana-folder` annotation | Sets which folder in Grafana UI | `"/"` or `"/MyApp"` |

**For datasources:**
| Label/Annotation | Purpose | Example |
|-----------------|---------|---------|
| `grafana_datasource=1` | Tells sidecar to load datasource | Needed if using ConfigMap approach |

---

## 5. Complete Setup Flow (Step-by-Step)

### Prerequisites
```
✅ Grafana deployed (via kube-prometheus-stack or standalone)
✅ Prometheus, Loki, Tempo running (where your data is stored)
✅ Your app exporting telemetry (metrics, logs, traces)
```

### Step 1: Deploy Data Sources (if not already configured)

**Check if already configured:**
```bash
# In Grafana UI: Configuration → Data Sources
# If you see Prometheus, Loki, Tempo → Skip to Step 2
```

**If not configured, enable in our chart:**
```yaml
# values.yaml
grafana:
  datasources:
    enabled: true  # <-- Enable datasource ConfigMap
    namespace: "observability"
    prometheus:
      enabled: true
      url: "http://prometheus-server:9090"
    loki:
      enabled: true
      url: "http://loki:3100"
    tempo:
      enabled: true
      url: "http://tempo:3200"
```

### Step 2: Deploy Dashboards (Automatic!)

**Our chart does this automatically:**
```yaml
# values.yaml
grafana:
  dashboards:
    enabled: true  # <-- Already enabled by default!
    namespace: "observability"
    folder: "/"
```

**What happens:**
1. Helm creates 3 ConfigMaps (one per dashboard)
2. Each ConfigMap has label `grafana_dashboard=1`
3. kube-prometheus-stack sidecar detects them
4. Dashboards appear in Grafana UI automatically!

### Step 3: Verify in Grafana

**Access Grafana:**
```bash
kubectl port-forward -n observability svc/prometheus-grafana 3000:80
# Open http://localhost:3000 (admin/admin)
```

**Check Dashboards:**
1. Go to **Dashboards → Browse**
2. You should see:
   - "dm-nkp-gitops-custom-app - Metrics"
   - "dm-nkp-gitops-custom-app - Logs"
   - "dm-nkp-gitops-custom-app - Traces"

**Check Data Sources:**
1. Go to **Configuration → Data Sources**
2. You should see: Prometheus, Loki, Tempo

---

## 6. Troubleshooting Checklist

### Dashboards not showing up?

**Check 1: ConfigMap exists with correct label**
```bash
kubectl get configmap -n observability -l grafana_dashboard=1
# Should list your dashboard ConfigMaps
```

**Check 2: Sidecar is running**
```bash
kubectl get pod -n observability -l app.kubernetes.io/name=grafana
# Check if sidecar container is running
```

**Check 3: Check Grafana logs**
```bash
kubectl logs -n observability -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard
# Sidecar logs will show dashboard import status
```

**Check 4: Verify namespace**
```bash
# Make sure dashboards are in same namespace as Grafana
kubectl get configmap -n observability | grep dashboard
```

### Data Sources not working?

**Check 1: Data source ConfigMap exists**
```bash
kubectl get configmap -n observability -l grafana_datasource=1
```

**Note:** For kube-prometheus-stack, datasources are usually configured via Helm values, not ConfigMaps. Check your kube-prometheus-stack values:

```yaml
grafana:
  additionalDataSources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server:9090
```

**Check 2: Test connection in Grafana UI**
- Go to Configuration → Data Sources → Prometheus → Test

---

## 7. Quick Reference: What Happens Automatically

### With Our Chart (kube-prometheus-stack)

✅ **Dashboards**: Auto-discovered (just need label `grafana_dashboard=1`)
✅ **Provider**: Not needed (sidecar handles it automatically)
⚠️ **Datasources**: Usually configured via Helm values, but ConfigMap works if sidecar has `datasources.enabled=true`

### What Our Chart Does

1. **Creates 3 Dashboard ConfigMaps** (metrics, logs, traces)
   - Labels: `grafana_dashboard=1`
   - Namespace: `observability` (or configured namespace)
   - Auto-discovered by Grafana sidecar

2. **Creates 1 Datasource ConfigMap** (optional)
   - Labels: `grafana_datasource=1`
   - Only works if Grafana sidecar has datasource provisioning enabled
   - Usually datasources are configured via Helm values instead

3. **Provider ConfigMap** (created but optional)
   - Only needed for custom folder organization
   - kube-prometheus-stack doesn't need it (has built-in provider)

---

## 8. Key Takeaways

1. **Dashboards = JSON files in ConfigMaps** with label `grafana_dashboard=1`
2. **Data Sources = Connection config** to Prometheus/Loki/Tempo (usually in Helm values)
3. **Provider = Optional** for kube-prometheus-stack (auto-discovery handles it)
4. **Auto-Discovery = Sidecar watches** for ConfigMaps and imports them automatically
5. **Namespace matters** - Everything should be in same namespace as Grafana

---

## 9. Common Questions

**Q: Do I need to restart Grafana after deploying dashboards?**
A: No! The sidecar auto-refreshes when ConfigMaps change.

**Q: Can I edit dashboards in Grafana UI?**
A: Yes, but edits are temporary. To persist, update the ConfigMap and redeploy.

**Q: Why aren't my datasources showing up?**
A: For kube-prometheus-stack, datasources are typically configured via Helm values (`grafana.additionalDataSources`), not ConfigMaps. The ConfigMap approach only works if Grafana has datasource sidecar enabled.

**Q: Can I have multiple dashboard ConfigMaps?**
A: Yes! All ConfigMaps with label `grafana_dashboard=1` are automatically discovered.

**Q: How do I organize dashboards into folders?**
A: Use the `grafana-folder` annotation on your dashboard ConfigMap:
```yaml
annotations:
  grafana-folder: "/MyApp"
```

---

## Summary: The Simplest Explanation

**Getting Grafana dashboards running = 3 steps:**

1. **Data exists** (Prometheus has metrics, Loki has logs, Tempo has traces)
2. **Data sources configured** (Grafana knows where to find the data)
3. **Dashboard ConfigMaps deployed** (with label `grafana_dashboard=1`)

**Everything else is automatic!** The sidecar does the rest.

---

For more details, see:
- [Grafana Dashboard Setup](GRAFANA_DASHBOARDS_SETUP.md)
- [OpenTelemetry Quick Start](OPENTELEMETRY_QUICK_START.md)
