# Capturing stdout/stderr Logs to Loki

## Current Situation

### What Happens to stdout/stderr Logs?

**Short answer**: stdout/stderr logs currently **DO NOT go to Loki** with the current OTel Collector configuration.

### Current Architecture

```
Application
├─→ OTLP logs (via telemetry.LogInfo()) → OTel Collector → Loki ✅
└─→ stdout/stderr logs (via log.Printf()) → Kubernetes logs only ❌ (not in Loki)
```

### Why stdout/stderr Logs Don't Go to Loki

The current OTel Collector configuration only has an **OTLP receiver**:

```yaml
receivers:
  otlp:  # Only receives OTLP protocol logs
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
```

**OTLP receiver** only accepts logs sent via the OTLP protocol. It does NOT read stdout/stderr from containers.

## Options to Capture stdout/stderr Logs

### Option 1: Use OTel Collector filelog Receiver (Recommended)

**No logging operator needed** - OTel Collector can handle it directly!

#### How It Works

```
Application → stdout/stderr → Container Runtime → /var/log/pods/ → OTel Collector (filelog) → Loki
```

#### Configuration

Deploy OTel Collector in **DaemonSet mode** with `filelog` receiver:

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector-logs
  namespace: observability
spec:
  mode: daemonset  # DaemonSet runs on every node
  config:
    receivers:
      # OTLP receiver (for direct OTLP logs)
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      
      # filelog receiver (for stdout/stderr logs)
      filelog:
        include:
          - /var/log/pods/**/*.log
        exclude:
          - /var/log/pods/**/*previous.log
        operators:
          # Parse JSON log format (Kubernetes default)
          - type: json_parser
            id: parser-json
            output: extract_metadata_from_filepath
          
          # Extract pod metadata from file path
          - type: regex_parser
            id: extract_metadata_from_filepath
            regex: '^.*\/(?P<namespace>[^_]+)_(?P<pod_name>[^_]+)_(?P<uid>[^\/]+)\/(?P<container_name>[^\.]+)\.log$'
            parse_from: attributes["log.file.path"]
            output: add_kubernetes_metadata
    
    processors:
      batch: {}
      resource:
        attributes:
          - key: job
            value: otel-collector
            action: upsert
      # Add Kubernetes metadata to logs
      k8sattributes:
        auth_type: serviceAccount
        passthrough: false
        extract:
          metadata:
            - pod_name
            - pod_uid
            - namespace
            - node_name
          labels:
            - tag_name: app.kubernetes.io/name
              key: app_kubernetes_io_name
            - tag_name: app.kubernetes.io/instance
              key: app_kubernetes_io_instance
          annotations:
            - tag_name: app.kubernetes.io/version
              key: app_kubernetes_io_version
    
    exporters:
      otlphttp/loki:
        endpoint: http://loki-loki-distributed-gateway.observability.svc.cluster.local:80/otlp
      debug:
        verbosity: normal
    
    service:
      pipelines:
        logs:
          receivers: [otlp, filelog]  # Both OTLP and filelog
          processors: [k8sattributes, batch, resource]
          exporters: [otlphttp/loki, debug]
```

#### Deployment Requirements

**DaemonSet mode requires:**

- ServiceAccount with permissions to read pod metadata
- Volume mount to `/var/log` (hostPath)
- Access to Kubernetes API for metadata enrichment

**ServiceAccount:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: otel-collector-logs
  namespace: observability
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: otel-collector-logs
rules:
- apiGroups: [""]
  resources: ["pods", "namespaces"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: otel-collector-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: otel-collector-logs
subjects:
- kind: ServiceAccount
  name: otel-collector-logs
  namespace: observability
```

#### Pros and Cons

**Pros:**

- ✅ No logging operator needed
- ✅ Uses standard OTel Collector
- ✅ Can collect both OTLP and stdout/stderr logs
- ✅ Automatic Kubernetes metadata enrichment
- ✅ Single component to maintain

**Cons:**

- ❌ Requires DaemonSet deployment
- ❌ Needs access to host filesystem (`/var/log`)
- ❌ Security considerations (hostPath volumes)
- ❌ More complex configuration

### Option 2: Use Logging Operator (Not Recommended)

**Why not recommended:**

- ❌ Grafana Agent Operator is EOL/deprecated
- ❌ Adds extra components
- ❌ More complex architecture
- ❌ Not standard OpenTelemetry approach

**If you must use it:**

- Fluent Bit/D (logging operator)
- Grafana Agent (deprecated)
- Vector (alternative)

### Option 3: Keep Using OTLP Only (Current Approach - Best)

**Recommended for modern applications:**

```
Application → OTLP → OTel Collector → Loki ✅
```

**Pros:**

- ✅ Standard OpenTelemetry approach
- ✅ No extra components
- ✅ Better performance
- ✅ Consistent with metrics and traces
- ✅ No host filesystem access needed

**Cons:**

- ❌ Requires application code changes (already done!)
- ❌ Third-party libraries that log to stdout won't be captured

## Recommendation

### For Your Application

**Current setup (OTLP only) is recommended** because:

1. ✅ **Application already sends logs via OTLP** (after code update)
2. ✅ **No infrastructure changes needed**
3. ✅ **Standard OpenTelemetry approach**
4. ✅ **Better performance and maintainability**

### When to Use filelog Receiver

Use `filelog` receiver if you need to capture:

- ❌ Logs from third-party libraries that log to stdout/stderr
- ❌ Logs from unmodifiable legacy applications
- ❌ System-level logs
- ❌ Logs from applications you cannot modify

### Hybrid Approach

You can use **both**:

1. **OTLP receiver** for your application logs (current setup)
2. **filelog receiver** (DaemonSet) for stdout/stderr from other sources

```yaml
service:
  pipelines:
    logs:
      receivers: [otlp, filelog]  # Both!
      processors: [k8sattributes, batch, resource]
      exporters: [otlphttp/loki]
```

## Summary

### Current State

- ✅ **OTLP logs** → OTel Collector → Loki (working)
- ❌ **stdout/stderr logs** → Kubernetes logs only (NOT in Loki)

### To Capture stdout/stderr

**Option 1 (Recommended if needed)**: Add `filelog` receiver to OTel Collector in DaemonSet mode

- No logging operator needed
- OTel Collector can handle it
- Requires DaemonSet deployment

**Option 2 (Not recommended)**: Use logging operator

- EOL/deprecated products
- Extra components
- More complexity

**Option 3 (Best for your app)**: Keep using OTLP only

- Standard approach
- Already implemented
- No infrastructure changes

### Answer to Your Question

**Q: What will happen if I have some logs going to stdout, will they not go to Loki?**

**A**: Correct - stdout/stderr logs currently **do NOT go to Loki**. They only go to Kubernetes logs (`kubectl logs`).

**Q: Do I need to use logging operator for them or otel collector can handle such logs?**

**A**: **OTel Collector CAN handle stdout/stderr logs** using the `filelog` receiver. You do **NOT need a logging operator**. However, you need to:

1. Deploy OTel Collector in DaemonSet mode
2. Add `filelog` receiver configuration
3. Mount `/var/log` volume

**Recommendation**: Since your application now sends logs via OTLP, you probably don't need to capture stdout/stderr. But if you do, use OTel Collector's `filelog` receiver (no logging operator needed).
