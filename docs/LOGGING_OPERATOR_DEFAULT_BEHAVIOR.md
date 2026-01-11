# Logging Operator Default Behavior: Collection Scope & Exclusions

## Quick Answer

**It depends on how the platform team configured it**, but generally:

1. **Fluent Bit DaemonSet** (the log collector) reads from `/var/log/containers` on each node, which contains logs from **all pods on that node**
2. **Without Flow/ClusterFlow CRs**: Logs are collected but **not routed anywhere** (wasted resources)
3. **With ClusterFlow CR**: Can collect from **all namespaces by default** (unless exclusions are configured)
4. **With Flow CR**: Only collects from the **specific namespace** where the Flow is defined
5. **Exclusions**: Can be configured via labels, match rules, or Flow/ClusterFlow selectors

## Understanding Logging Operator Architecture

### Components

```
┌─────────────────────────────────────────────────────────┐
│              KUBERNETES NODES                            │
│  ┌─────────────────────────────────────────┐            │
│  │  All Pods (all namespaces)              │            │
│  │  └─> stdout/stderr → /var/log/containers│            │
│  └─────────────────────────────────────────┘            │
└───────────────────────┬─────────────────────────────────┘
                        │ (read by Fluent Bit)
                        ▼
┌─────────────────────────────────────────────────────────┐
│         FLUENT BIT (DaemonSet on each node)              │
│  ┌─────────────────────────────────────────┐            │
│  │  Reads /var/log/containers              │            │
│  │  (ALL container logs on the node)       │            │
│  └─────────────────────────────────────────┘            │
└───────────────────────┬─────────────────────────────────┘
                        │ (processes based on Flow/ClusterFlow CRs)
                        ▼
┌─────────────────────────────────────────────────────────┐
│         LOGGING OPERATOR                                 │
│  ┌─────────────────────────────────────────┐            │
│  │  Flow CRs → Namespace-scoped routing    │            │
│  │  ClusterFlow CRs → Cluster-wide routing │            │
│  └─────────────────────────────────────────┘            │
└───────────────────────┬─────────────────────────────────┘
                        │ (routes to Output/ClusterOutput)
                        ▼
                    [Loki, S3, etc.]
```

### Key Points

1. **Fluent Bit reads ALL logs** from `/var/log/containers` on each node (includes all pods, all namespaces)
2. **Flow/ClusterFlow CRs** determine which logs get processed and routed
3. **Without CRs**: Logs are read but not forwarded (collected but dropped)

## Default Behavior Scenarios

### Scenario 1: No Flow/ClusterFlow CRs Configured

**What Happens:**
- ✅ Fluent Bit DaemonSet is running on each node
- ✅ Fluent Bit reads from `/var/log/containers` (all pod logs)
- ❌ **No Flow/ClusterFlow CRs exist** → Logs are collected but **not routed anywhere**
- ❌ Logs are **wasted** (CPU/memory used, but nothing happens with logs)

**Result:** Logs are collected but not forwarded to Loki or any output destination.

**Is this common?** No - platform teams usually configure at least a default ClusterFlow.

### Scenario 2: ClusterFlow CR Configured (Default Collection)

**Example ClusterFlow (collects from all namespaces):**
```yaml
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterFlow
metadata:
  name: default-logs
spec:
  match:  # No match = matches everything (all namespaces)
    - select: {}  # Empty select matches all
  globalOutputRefs:
    - default-loki  # Routes to ClusterOutput
```

**What Happens:**
- ✅ Fluent Bit reads from `/var/log/containers` (all pod logs)
- ✅ ClusterFlow matches **all logs** (no restrictions)
- ✅ Logs are routed to the configured output (e.g., Loki)

**Result:** **All logs from all namespaces are collected and forwarded.**

### Scenario 3: ClusterFlow with Exclusions

**Example ClusterFlow with namespace exclusion:**
```yaml
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterFlow
metadata:
  name: app-logs-exclude-system
spec:
  match:
    - select: {}  # Select all first
      exclude:    # Then exclude
        namespaces:
          - kube-system
          - kube-public
          - kube-node-lease
  globalOutputRefs:
    - default-loki
```

**What Happens:**
- ✅ Fluent Bit reads from `/var/log/containers` (all pod logs)
- ✅ ClusterFlow matches all logs **except** those from excluded namespaces
- ✅ Only application logs are routed to Loki

**Result:** **Most namespaces collected, system namespaces excluded.**

### Scenario 4: Flow CRs (Namespace-Scoped)

**Example Flow (only collects from specific namespace):**
```yaml
apiVersion: logging.banzaicloud.io/v1beta1
kind: Flow
metadata:
  name: production-logs
  namespace: production  # <-- Only this namespace
spec:
  match:
    - select:
        namespaces:
          - production  # Explicitly select this namespace
  localOutputRefs:
    - production-loki  # Routes to Output in same namespace
```

**What Happens:**
- ✅ Fluent Bit reads from `/var/log/containers` (all pod logs)
- ✅ Flow only processes logs from `production` namespace
- ✅ Logs from other namespaces are **ignored** by this Flow

**Result:** **Only logs from `production` namespace are collected.**

**Note:** You can have multiple Flow CRs, one per namespace, to selectively collect logs.

## Common Exclusion Methods

### Method 1: Exclude via ClusterFlow Match Rules

```yaml
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterFlow
metadata:
  name: app-logs-only
spec:
  match:
    - select: {}  # Select all
      exclude:
        namespaces:
          - kube-system
          - kube-public
        labels:
          app: test-app  # Exclude pods with this label
  globalOutputRefs:
    - default-loki
```

**Excludes:**
- All pods in `kube-system` namespace
- All pods in `kube-public` namespace
- All pods with label `app: test-app`

### Method 2: Exclude via Pod/Namespace Labels

**Add label to namespace:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-namespace
  labels:
    log-shipper.deckhouse.io/exclude: "true"  # Some platforms support this
    # OR platform-specific label
    logging.banzaicloud.io/exclude: "true"  # Check platform docs
```

**Add label to pod:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  labels:
    logging.banzaicloud.io/exclude: "true"  # Exclude this pod
```

**Note:** Label names may vary by platform. Check your platform team's documentation.

### Method 3: Selective Collection (Only Include What You Want)

```yaml
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterFlow
metadata:
  name: app-logs-only
spec:
  match:
    - select:
        namespaces:
          - production
          - staging
        labels:
          app.kubernetes.io/managed-by: helm  # Only Helm-managed apps
  globalOutputRefs:
    - default-loki
```

**Only collects logs from:**
- `production` and `staging` namespaces
- Pods with label `app.kubernetes.io/managed-by: helm`

### Method 4: Multiple Flows (Selective per Namespace)

```yaml
# Flow for production
apiVersion: logging.banzaicloud.io/v1beta1
kind: Flow
metadata:
  name: production-logs
  namespace: production
spec:
  match:
    - select:
        namespaces: [production]
  localOutputRefs:
    - production-loki

---
# Flow for staging
apiVersion: logging.banzaicloud.io/v1beta1
kind: Flow
metadata:
  name: staging-logs
  namespace: staging
spec:
  match:
    - select:
        namespaces: [staging]
  localOutputRefs:
    - staging-loki
```

**Result:** Only `production` and `staging` logs are collected. All other namespaces are ignored.

## How to Check Your Platform's Configuration

### Step 1: Check if Logging Operator is Installed

```bash
# Check for Logging Operator deployment
kubectl get deployment -A | grep logging-operator

# Check for Fluent Bit DaemonSet
kubectl get daemonset -A | grep fluent-bit
```

### Step 2: Check Flow/ClusterFlow CRs

```bash
# List all ClusterFlows (cluster-wide collection rules)
kubectl get clusterflow -A

# List all Flows (namespace-scoped collection rules)
kubectl get flow -A

# View a ClusterFlow configuration
kubectl get clusterflow default-logs -o yaml
```

### Step 3: Check What's Being Collected

```bash
# Check Fluent Bit pods (one per node)
kubectl get pods -n logging-system -l app=fluent-bit

# View Fluent Bit logs to see what it's processing
kubectl logs -n logging-system -l app=fluent-bit --tail=100

# Check for your application's logs in Loki
# (if you have access to Grafana/Loki)
```

### Step 4: Check for Exclusion Labels

```bash
# Check if your namespace has exclusion labels
kubectl get namespace your-namespace -o yaml | grep -i exclude

# Check if your pods have exclusion labels
kubectl get pods -n your-namespace -o yaml | grep -i exclude
```

## Production Platform Team Setup (Common Pattern)

**Typical platform team configuration:**

```yaml
# Default ClusterFlow: Collect everything except system namespaces
apiVersion: logging.banzaicloud.io/v1beta1
kind: ClusterFlow
metadata:
  name: default-app-logs
spec:
  match:
    - select: {}
      exclude:
        namespaces:
          - kube-system
          - kube-public
          - kube-node-lease
          - logging-system  # Exclude logging operator itself
        labels:
          # Exclude test/debug pods
          logging.banzaicloud.io/exclude: "true"
  globalOutputRefs:
    - default-loki
```

**This setup:**
- ✅ Collects logs from **all application namespaces**
- ❌ Excludes system namespaces (`kube-system`, etc.)
- ❌ Excludes pods with exclusion labels
- ✅ Routes all collected logs to Loki

## What This Means for Your Application

### If Your Namespace is NOT Excluded

**Default behavior (most common):**
- ✅ Your application logs (stdout/stderr) **will be collected**
- ✅ Logs will be forwarded to Loki (or configured output)
- ✅ **No action needed** - logs are automatically collected

### If Your Namespace IS Excluded

**You'll see:**
- ❌ Your application logs are **not collected**
- ❌ No logs appear in Loki
- ✅ **Action needed**: Work with platform team to include your namespace, or disable OTel Collector log collection

### To Check if Your Logs Are Being Collected

```bash
# Check if logs from your namespace appear in Fluent Bit logs
kubectl logs -n logging-system -l app=fluent-bit | grep your-namespace

# Check Loki (if accessible) for your application logs
# Query Loki: {namespace="your-namespace"}
```

## Best Practices

### For Platform Teams

1. **Configure explicit ClusterFlow** - Don't leave it unconfigured (wasted resources)
2. **Document exclusion list** - Make it clear what's excluded and why
3. **Provide exclusion mechanism** - Allow app teams to exclude their namespace if needed
4. **Monitor collection** - Alert if Fluent Bit isn't processing logs

### For Application Teams

1. **Assume logs are collected** - Unless explicitly told otherwise
2. **Check platform documentation** - See what the default configuration is
3. **Verify in production** - Confirm your logs appear in Loki/Grafana
4. **Coordinate with platform team** - If you need exclusions or have concerns

## FAQ

### Q: Does Logging Operator collect logs from ALL containers by default?

**A:** **Technically yes**, Fluent Bit reads from `/var/log/containers` which contains all container logs. However, **Flow/ClusterFlow CRs determine what actually gets routed**. Without CRs, logs are collected but not forwarded. Most platform teams configure a ClusterFlow that collects most namespaces but excludes system namespaces.

### Q: Can I exclude my namespace from log collection?

**A:** Yes, but it depends on platform configuration:
1. **Check with platform team** - They may have a label-based exclusion mechanism
2. **Add exclusion label** - If supported (e.g., `logging.banzaicloud.io/exclude: "true"`)
3. **Modify ClusterFlow** - Platform team can add your namespace to exclusion list
4. **Use separate Flow** - Create a Flow CR that explicitly excludes your namespace (advanced)

### Q: Will excluding my namespace save resources?

**A:** **No, not significantly.** Fluent Bit still reads from `/var/log/containers` (all logs). Exclusion only prevents **routing/processing** of those logs. To truly save resources, you'd need to configure Fluent Bit itself to skip reading those files (platform-level change).

### Q: How do I know what's being collected in my environment?

**A:** 
1. Check ClusterFlow/Flow CRs: `kubectl get clusterflow,flow -A`
2. Check Fluent Bit logs: `kubectl logs -n logging-system -l app=fluent-bit`
3. Query Loki/Grafana for your namespace logs
4. Ask platform team for documentation

### Q: What if I have both OTel Collector and Logging Operator collecting logs?

**A:** You'll get **duplicate logs**. See [DUPLICATE_LOG_COLLECTION.md](./DUPLICATE_LOG_COLLECTION.md) for how to handle this.

## Summary

| Scenario | Logs Collected? | Routed? | Action Needed |
|----------|----------------|---------|---------------|
| No Flow/ClusterFlow | ✅ Yes (all) | ❌ No | Platform team should configure |
| ClusterFlow (no exclusions) | ✅ Yes (all) | ✅ Yes | ✅ Default - logs collected |
| ClusterFlow (with exclusions) | ✅ Yes (selective) | ✅ Yes | ✅ Check if your namespace is excluded |
| Flow (namespace-scoped) | ✅ Yes (specific namespace) | ✅ Yes | ✅ Only that namespace collected |
| Your namespace has exclusion label | ❌ No | ❌ No | ⚠️ Logs not collected - coordinate with platform |

**Most common setup:** ClusterFlow that collects all application namespaces but excludes system namespaces.

## Related Documentation

- [DUPLICATE_LOG_COLLECTION.md](./DUPLICATE_LOG_COLLECTION.md) - Avoiding duplicate logs with OTel Collector
- [LOGGING_OPERATOR_EXPLANATION.md](./LOGGING_OPERATOR_EXPLANATION.md) - Overview of Logging Operator
