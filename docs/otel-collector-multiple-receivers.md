# Using Multiple Receivers in OpenTelemetry Collector

## Answer: Yes, They Can Work Together

**OTLP and filelog receivers are NOT mutually exclusive** - you can use both together in the same OTel Collector instance.

## How It Works

### Multiple Receivers in Same Pipeline

You can configure multiple receivers and use them in the same pipeline:

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: observability
spec:
  mode: deployment  # or daemonset for filelog
  config:
    receivers:
      # OTLP receiver (for direct OTLP logs from applications)
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      
      # filelog receiver (for stdout/stderr logs from containers)
      filelog:
        include:
          - /var/log/pods/**/*.log
        exclude:
          - /var/log/pods/**/*previous.log
        operators:
          - type: json_parser
            id: parser-json
            output: extract_metadata_from_filepath
          - type: regex_parser
            id: extract_metadata_from_filepath
            regex: '^.*\/(?P<namespace>[^_]+)_(?P<pod_name>[^_]+)_(?P<uid>[^\/]+)\/(?P<container_name>[^\.]+)\.log$'
            parse_from: attributes["log.file.path"]
    
    processors:
      batch: {}
      resource:
        attributes:
          - key: job
            value: otel-collector
            action: upsert
      # Add Kubernetes metadata (useful for filelog logs)
      k8sattributes:
        auth_type: serviceAccount
        passthrough: false
        extract:
          metadata:
            - pod_name
            - pod_uid
            - namespace
          labels:
            - tag_name: app.kubernetes.io/name
              key: app_kubernetes_io_name
    
    exporters:
      otlphttp/loki:
        endpoint: http://loki-loki-distributed-gateway.observability.svc.cluster.local:80/otlp
      debug:
        verbosity: normal
    
    service:
      pipelines:
        logs:
          # Use BOTH receivers in the same pipeline!
          receivers: [otlp, filelog]
          processors: [k8sattributes, batch, resource]
          exporters: [otlphttp/loki, debug]
```

### Result

With this configuration:

- ✅ **OTLP logs** (from your application) → OTLP receiver → Loki
- ✅ **stdout/stderr logs** (from containers) → filelog receiver → Loki
- ✅ **Both types** processed by the same pipeline and sent to Loki

## Deployment Modes

### Option 1: Single Deployment (Both Receivers)

**For Deployment mode:**

- ✅ OTLP receiver works (listens on ports)
- ❌ filelog receiver **won't work** (needs access to `/var/log` on nodes)

**Limitation**: Deployment mode doesn't have access to host filesystem where container logs are stored.

### Option 2: DaemonSet Mode (Both Receivers)

**For DaemonSet mode:**

- ✅ OTLP receiver works (listens on ports)
- ✅ filelog receiver works (has access to `/var/log` on each node)

**This is the recommended approach** if you want both receivers.

### Option 3: Separate Collectors (Different Modes)

You can deploy **two separate collectors**:

1. **Deployment mode** for OTLP:

   ```yaml
   apiVersion: opentelemetry.io/v1beta1
   kind: OpenTelemetryCollector
   metadata:
     name: otel-collector-otlp
   spec:
     mode: deployment
     config:
       receivers:
         otlp: {...}
       service:
         pipelines:
           logs:
             receivers: [otlp]
   ```

2. **DaemonSet mode** for filelog:

   ```yaml
   apiVersion: opentelemetry.io/v1beta1
   kind: OpenTelemetryCollector
   metadata:
     name: otel-collector-filelog
   spec:
     mode: daemonset
     config:
       receivers:
         filelog: {...}
       service:
         pipelines:
           logs:
             receivers: [filelog]
   ```

## Complete Example: Both Receivers in DaemonSet

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: observability
spec:
  mode: daemonset  # Required for filelog to access /var/log
  serviceAccount: otel-collector
  config:
    receivers:
      # OTLP receiver - receives logs sent via OTLP protocol
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      
      # filelog receiver - reads stdout/stderr from container logs
      filelog:
        include:
          - /var/log/pods/**/*.log
        exclude:
          - /var/log/pods/**/*previous.log
        operators:
          - type: json_parser
            id: parser-json
            output: extract_metadata_from_filepath
          - type: regex_parser
            id: extract_metadata_from_filepath
            regex: '^.*\/(?P<namespace>[^_]+)_(?P<pod_name>[^_]+)_(?P<uid>[^\/]+)\/(?P<container_name>[^\.]+)\.log$'
            parse_from: attributes["log.file.path"]
    
    processors:
      batch: {}
      resource:
        attributes:
          - key: job
            value: otel-collector
            action: upsert
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
    
    exporters:
      otlphttp/loki:
        endpoint: http://loki-loki-distributed-gateway.observability.svc.cluster.local:80/otlp
      debug:
        verbosity: normal
    
    service:
      pipelines:
        logs:
          # Both receivers feed into the same pipeline!
          receivers: [otlp, filelog]
          processors: [k8sattributes, batch, resource]
          exporters: [otlphttp/loki, debug]
```

## Key Points

### ✅ They Work Together

- Multiple receivers can be defined in the same config
- Multiple receivers can be used in the same pipeline
- Logs from different sources are merged in the pipeline
- Same processors and exporters handle all logs

### ⚠️ Deployment Mode Limitation

- **Deployment mode**: OTLP works, filelog **doesn't work** (no host filesystem access)
- **DaemonSet mode**: Both OTLP and filelog work

### 📊 Log Flow

```
Application (OTLP) ──┐
                      ├─→ OTel Collector Pipeline ─→ Loki
Containers (stdout) ──┘
```

Both sources → Same pipeline → Same exporter → Loki

## When to Use Both

### Use Both Receivers If

1. ✅ You have applications sending logs via OTLP (your app)
2. ✅ You need to capture stdout/stderr from:
   - Third-party libraries
   - Unmodifiable legacy applications
   - System components
   - Applications you can't modify

### Use Only OTLP If

1. ✅ All your applications can send logs via OTLP
2. ✅ You don't need to capture stdout/stderr
3. ✅ You want simpler architecture (Deployment mode)

## Current Recommendation for Your Setup

### Current State

- ✅ OTLP receiver configured (Deployment mode)
- ❌ filelog receiver not configured

### Recommendation

**Option 1 (Recommended)**: Keep OTLP only

- Your application now sends logs via OTLP
- Simpler architecture
- No host filesystem access needed
- Standard OpenTelemetry approach

**Option 2 (If needed)**: Add filelog receiver

- Switch to DaemonSet mode
- Add filelog receiver configuration
- Configure ServiceAccount and RBAC
- Mount `/var/log` volume

## Summary

| Question | Answer |
|----------|--------|
| Can OTLP and filelog work together? | ✅ **Yes, absolutely!** |
| Are they mutually exclusive? | ❌ **No, they can coexist** |
| Can they use the same pipeline? | ✅ **Yes, same pipeline** |
| Deployment mode limitation? | ⚠️ **filelog needs DaemonSet mode** |
| Recommended approach? | ✅ **OTLP only (current setup)** |

**Bottom line**: They are **NOT mutually exclusive** - you can use both together in the same OTel Collector instance, but filelog requires DaemonSet mode to access container logs.
