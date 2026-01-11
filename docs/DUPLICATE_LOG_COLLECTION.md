# Avoiding Duplicate Log Collection: OTel Collector vs Logging Operator

## The Problem

In production, if **both** OpenTelemetry Collector and Logging Operator are collecting logs, you will get **duplicate logs** in Loki, wasting storage and causing confusion.

## Understanding Current Log Flow

### How Your Application Logs

Your Go application uses standard logging to stdout/stderr:
```go
log.Printf("[INFO] Application starting")
log.Printf("[ERROR] Something went wrong: %v", err)
```

These logs are written to the container's stdout/stderr streams.

### Two Ways Logs Get Collected

#### Option 1: OpenTelemetry Collector (OTLP Receiver)
- OTel Collector receives logs **via OTLP protocol** (gRPC/HTTP)
- Application must **explicitly export** logs using OpenTelemetry SDK
- **Current Status**: ❌ Your app does **NOT** export logs via OTLP
- OTel Collector's logs pipeline only receives logs sent via OTLP protocol

#### Option 2: Logging Operator + Fluent Bit
- Logging Operator deploys **Fluent Bit as DaemonSet** on each node
- Fluent Bit **automatically collects** stdout/stderr from all pods
- **No code changes** needed - works with any application
- **Current Status**: ✅ If deployed by platform team, this WILL collect your logs

## When Duplicates Occur

### Scenario 1: Both Collecting (❌ Problem)
```
Application (stdout/stderr)
├──→ OTel Collector (via OTLP) → Loki  [Duplicate #1]
└──→ Fluent Bit (via Logging Operator) → Loki  [Duplicate #2]
```
**Result**: Same logs stored twice in Loki = 2x storage cost + confusion

### Scenario 2: Current Setup (✅ No Duplicates Yet)
```
Application (stdout/stderr)
├──→ OTel Collector (logs pipeline enabled but not receiving OTLP logs) → ❌ No logs collected
└──→ Fluent Bit (if Logging Operator is deployed) → Loki  ✅ Only one collection
```
**Result**: No duplicates because OTel Collector's logs pipeline isn't actually collecting stdout/stderr

### Scenario 3: Production Best Practice (✅ Recommended)
```
Application (stdout/stderr)
├──→ OTel Collector (logs pipeline DISABLED) → ❌ Logs not collected here
└──→ Fluent Bit (via Logging Operator) → Loki  ✅ Single collection point
```
**Result**: Logging Operator handles logs, OTel Collector handles metrics/traces only

## Solution: Disable Log Collection in OTel Collector

### For Production (with Logging Operator)

**Update `chart/observability-stack/values.yaml`** (or override in production):

```yaml
otel-collector:
  enabled: true
  logs:
    enabled: false  # ✅ Disable log collection - Logging Operator handles it
```

**Or override during Helm install:**
```bash
helm upgrade --install observability-stack ./chart/observability-stack \
  --namespace observability \
  --set otel-collector.logs.enabled=false
```

### For Local Testing (without Logging Operator)

**Keep log collection enabled:**
```yaml
otel-collector:
  enabled: true
  logs:
    enabled: true  # ✅ Enable log collection - no Logging Operator in local
```

## What Happens After Disabling Log Pipeline?

### OTel Collector Still Handles:
- ✅ **Metrics** - Collected via OTLP, exported to Prometheus
- ✅ **Traces** - Collected via OTLP, exported to Tempo
- ❌ **Logs** - Disabled, Logging Operator handles this

### Logging Operator Handles:
- ✅ **Logs** - Automatically collects stdout/stderr from all pods
- ✅ **Forward to Loki** - Via Fluent Bit → Loki Push API

## Configuration Reference

### Observability Stack Values

```yaml
# chart/observability-stack/values.yaml
otel-collector:
  logs:
    enabled: true   # Local testing (no Logging Operator)
    # enabled: false # Production (Logging Operator present)
    lokiEndpoint: ""  # Optional: override Loki endpoint if needed
```

### Production Override

Create `chart/observability-stack/values-production.yaml`:
```yaml
otel-collector:
  logs:
    enabled: false  # Platform team deploys Logging Operator
```

Deploy:
```bash
helm upgrade --install observability-stack ./chart/observability-stack \
  --namespace observability \
  -f values-production.yaml
```

## Verification: Check for Duplicates

### Query Loki for Duplicates

```logql
# Count log lines by collection method
count by (fluentd_tag, otel_service_name) (
  {app="dm-nkp-gitops-custom-app"} |= "Application starting"
)
```

If you see:
- `fluentd_tag` present → Logs collected by Fluent Bit (Logging Operator)
- `otel_service_name` present → Logs collected by OTel Collector
- **Both present** → ⚠️ Duplicate collection detected!

### Check OTel Collector Config

```bash
kubectl get configmap -n observability observability-stack-otel-collector-config -o yaml
```

Look for `service.pipelines.logs`:
- **Present** → Log pipeline enabled (potential duplicate if Logging Operator exists)
- **Absent** → Log pipeline disabled (✅ correct if Logging Operator handles logs)

## Storage Impact

### Storage Calculation

**Without Duplication:**
- 1 application pod
- Logs: 100 MB/day
- **Total: 100 MB/day**

**With Duplication:**
- 1 application pod
- OTel Collector: 100 MB/day
- Fluent Bit: 100 MB/day
- **Total: 200 MB/day** (2x storage cost)

**For 100 pods:**
- Without duplication: 10 GB/day
- With duplication: 20 GB/day
- **Waste: 10 GB/day = 3650 GB/year** 💰

## Best Practices Summary

### ✅ Do:
1. **Disable OTel Collector log collection** if Logging Operator is deployed
2. **Let Logging Operator handle** stdout/stderr collection (automatic, no code changes)
3. **Use OTel Collector for metrics/traces only** when Logging Operator handles logs
4. **Verify in production** that logs aren't duplicated

### ❌ Don't:
1. **Don't enable both** log collection mechanisms simultaneously
2. **Don't configure OTel Collector to collect stdout/stderr** (filelog/k8sobjects receivers) if Logging Operator exists
3. **Don't assume** - verify which log collection is active in your environment

## Migration Path

### If You Already Have Duplicates

**Step 1**: Disable log collection in OTel Collector
```bash
kubectl patch configmap observability-stack-otel-collector-config \
  -n observability \
  --type json \
  -p='[{"op": "remove", "path": "/data/config.yaml/service/pipelines/logs"}]'
```

**Step 2**: Restart OTel Collector
```bash
kubectl rollout restart deployment observability-stack-otel-collector -n observability
```

**Step 3**: Verify duplicates stop appearing
```bash
# Check Loki for new logs (should only see Fluent Bit tags)
```

**Step 4**: Clean up duplicate logs (optional, may require Loki admin access)
```bash
# Contact platform team to remove duplicate log streams from Loki
```

## FAQ

### Q: Can I use OTel Collector for some apps and Logging Operator for others?

**A**: Yes! This is a valid hybrid approach:
- **OTel-instrumented apps**: Export logs via OTLP → OTel Collector → Loki
- **Legacy apps**: stdout/stderr → Fluent Bit (Logging Operator) → Loki

Configure OTel Collector to only collect logs from OTel-instrumented apps, and let Logging Operator handle the rest.

### Q: What if I want to use OTel Collector for all logs?

**A**: Then you should:
1. Configure OTel Collector with `filelog` or `k8sobjects` receiver to collect stdout/stderr
2. **Disable Logging Operator** (or configure it to exclude your namespace)
3. Use OTel Collector for all log collection

However, this is **not recommended** if platform team has standardized on Logging Operator.

### Q: How do I know if Logging Operator is deployed?

**A**: Check for Logging Operator resources:
```bash
# Check for Logging Operator CRDs
kubectl get crd | grep logging.banzaicloud.io

# Check for Fluent Bit DaemonSet
kubectl get daemonset -A | grep fluent-bit

# Check for Logging Operator deployment
kubectl get deployment -A | grep logging-operator

# Check Flow/ClusterFlow CRs (what's being collected)
kubectl get clusterflow,flow -A
```

See [LOGGING_OPERATOR_DEFAULT_BEHAVIOR.md](./LOGGING_OPERATOR_DEFAULT_BEHAVIOR.md) for detailed information on default collection behavior and exclusions.

### Q: Can I disable Logging Operator for my namespace?

**A**: Usually no - Logging Operator is cluster-wide. However, you can:
1. Configure Fluent Bit to **exclude** your namespace (via Flow CRs)
2. Work with platform team to configure log routing

**Recommended**: Coordinate with platform team to decide on a single log collection mechanism.

## Related Documentation

- [LOGGING_OPERATOR_EXPLANATION.md](./LOGGING_OPERATOR_EXPLANATION.md) - Overview of Logging Operator
- [LOGGING_OPERATOR_AND_PLATFORM_DEPENDENCIES.md](./LOGGING_OPERATOR_AND_PLATFORM_DEPENDENCIES.md) - Platform dependencies
- [OBSERVABILITY_STACK_COMPLETE.md](./OBSERVABILITY_STACK_COMPLETE.md) - OTel Collector configuration
