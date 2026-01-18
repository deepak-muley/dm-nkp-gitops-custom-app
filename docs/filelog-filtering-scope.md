# filelog Receiver Scope: Filtering Pod Logs

## Answer: It Captures ALL Pods by Default, But Can Be Filtered

**By default**, DaemonSet mode with `filelog` receiver captures logs from **ALL pods** on the node (including system pods).

**However**, you can filter to capture only your application's pods using several methods.

## Default Behavior

### What Gets Captured

When using `filelog` receiver in DaemonSet mode:

```
/var/log/pods/
├── default_dm-nkp-gitops-custom-app-xxx_uid/
│   └── app.log  ← Your app logs
├── kube-system_kube-proxy-xxx_uid/
│   └── kube-proxy.log  ← System pods
├── observability_prometheus-xxx_uid/
│   └── prometheus.log  ← Observability pods
└── ... (ALL pods on the node)
```

**Default**: All of these are captured.

## Filtering Methods

### Method 1: Filter by File Path Pattern (Recommended)

Use `include` patterns to match only your application's namespace and pod names:

```yaml
receivers:
  filelog:
    include:
      # Only capture logs from your app's namespace
      - /var/log/pods/default_dm-nkp-gitops-custom-app-*_*/*.log
      # Or capture all pods in your namespace
      - /var/log/pods/default_*_*/*.log
    exclude:
      # Exclude system namespaces
      - /var/log/pods/kube-system_*_*/*.log
      - /var/log/pods/kube-public_*_*/*.log
      - /var/log/pods/kube-node-lease_*_*/*.log
      # Exclude observability stack (if you don't want collector logs)
      - /var/log/pods/observability_*_*/*.log
    operators:
      - type: json_parser
        id: parser-json
        output: extract_metadata_from_filepath
      - type: regex_parser
        id: extract_metadata_from_filepath
        regex: '^.*\/(?P<namespace>[^_]+)_(?P<pod_name>[^_]+)_(?P<uid>[^\/]+)\/(?P<container_name>[^\.]+)\.log$'
        parse_from: attributes["log.file.path"]
```

**Example**: Capture only your app's namespace:

```yaml
include:
  - /var/log/pods/default_*_*/*.log  # Only 'default' namespace
```

### Method 2: Filter Using k8sattributes Processor

Use `k8sattributes` processor to filter based on Kubernetes labels:

```yaml
processors:
  k8sattributes:
    auth_type: serviceAccount
    passthrough: false
    # Filter: Only process logs from pods with specific labels
    filter:
      node_from_env_var: KUBE_NODE_NAME
    extract:
      metadata:
        - pod_name
        - pod_uid
        - namespace
      labels:
        - tag_name: app.kubernetes.io/name
          key: app_kubernetes_io_name
        - tag_name: app.kubernetes.io/instance
          key: app_kubernetes_io_instance
    # Filter logs based on labels (processor-level filtering)
    pod_association:
      - sources:
          - from: resource_attribute
            name: k8s.pod.uid
```

**Note**: `k8sattributes` processor can add metadata, but filtering at the processor level is limited. Better to filter at the receiver level.

### Method 3: Filter Using Resource Processor

Use `resource` processor to drop logs that don't match criteria:

```yaml
processors:
  resource:
    attributes:
      - key: namespace
        value: default
        action: keep_if_exists  # Only keep if namespace exists
      # Drop logs from system namespaces
      - key: namespace
        value: kube-system
        action: drop
      - key: namespace
        value: kube-public
        action: drop
```

**Note**: This is less efficient (processes then drops) compared to filtering at receiver level.

### Method 4: Filter Using Transform Processor (Advanced)

Use `transform` processor to filter based on attributes:

```yaml
processors:
  transform:
    log_statements:
      - context: log
        statements:
          # Drop logs from system namespaces
          - merge_maps(cache, {"namespace": attributes["namespace"]}, "upsert")
          - set(attributes["drop"], true) where attributes["namespace"] == "kube-system"
          - set(attributes["drop"], true) where attributes["namespace"] == "kube-public"
          - delete_key(attributes, "drop") where attributes["drop"] == true
```

## Recommended Configuration: Filter by Namespace

### Capture Only Your Application

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: observability
spec:
  mode: daemonset
  serviceAccount: otel-collector
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
      
      filelog:
        include:
          # Only capture logs from 'default' namespace (your app)
          - /var/log/pods/default_*_*/*.log
        exclude:
          # Explicitly exclude system namespaces
          - /var/log/pods/kube-system_*_*/*.log
          - /var/log/pods/kube-public_*_*/*.log
          - /var/log/pods/kube-node-lease_*_*/*.log
          # Exclude observability stack (optional)
          - /var/log/pods/observability_*_*/*.log
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
          labels:
            - tag_name: app.kubernetes.io/name
              key: app_kubernetes_io_name
    
    exporters:
      otlphttp/loki:
        endpoint: http://loki-loki-distributed-gateway.observability.svc.cluster.local:80/otlp
    
    service:
      pipelines:
        logs:
          receivers: [otlp, filelog]
          processors: [k8sattributes, batch, resource]
          exporters: [otlphttp/loki]
```

### Capture Multiple Specific Namespaces

```yaml
filelog:
  include:
    - /var/log/pods/default_*_*/*.log          # Your app namespace
    - /var/log/pods/production_*_*/*.log       # Production namespace
    - /var/log/pods/staging_*_*/*.log          # Staging namespace
  exclude:
    - /var/log/pods/kube-system_*_*/*.log      # System pods
    - /var/log/pods/observability_*_*/*.log     # Observability stack
```

### Capture Only Specific Pod Name Pattern

```yaml
filelog:
  include:
    # Only capture pods matching your app name pattern
    - /var/log/pods/*_dm-nkp-gitops-custom-app-*_*/*.log
  exclude:
    - /var/log/pods/kube-system_*_*/*.log
```

## File Path Pattern Format

### Understanding the Path Structure

Kubernetes stores logs in this format:

```
/var/log/pods/{namespace}_{pod-name}_{pod-uid}/{container-name}.log
```

**Example**:

```
/var/log/pods/default_dm-nkp-gitops-custom-app-58466f768d-bs75s_a1b2c3d4/app.log
│          │      │                              │              │      │
│          │      │                              │              │      └─ Container name
│          │      │                              │              └─ Pod UID
│          │      │                              └─ Pod name
│          │      └─ Namespace
│          └─ Base path
```

### Pattern Matching

- `*` matches any characters (except `/`)
- `**` matches any characters including `/` (for recursive)
- `?` matches single character

**Examples**:

```yaml
# All pods in default namespace
- /var/log/pods/default_*_*/*.log

# Specific app in any namespace
- /var/log/pods/*_dm-nkp-gitops-custom-app-*_*/*.log

# All pods in multiple namespaces
- /var/log/pods/{default,production,staging}_*_*/*.log
```

## Performance Considerations

### Filtering Efficiency

| Method | Efficiency | Recommendation |
|--------|-----------|---------------|
| **Receiver include/exclude** | ✅ Most efficient | **Recommended** - filters before processing |
| **Processor filtering** | ⚠️ Less efficient | Processes then drops - use as secondary filter |
| **No filtering** | ❌ Least efficient | Processes all logs - not recommended |

**Best practice**: Filter at the receiver level using `include`/`exclude` patterns.

## Complete Example: App-Only Logs

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: observability
spec:
  mode: daemonset
  serviceAccount: otel-collector
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
      
      filelog:
        include:
          # Only your app's namespace
          - /var/log/pods/default_*_*/*.log
        exclude:
          # Exclude system namespaces
          - /var/log/pods/kube-system_*_*/*.log
          - /var/log/pods/kube-public_*_*/*.log
          - /var/log/pods/kube-node-lease_*_*/*.log
        operators:
          - type: json_parser
            id: parser-json
          - type: regex_parser
            id: extract_metadata
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
        extract:
          metadata: [pod_name, namespace]
          labels:
            - tag_name: app.kubernetes.io/name
              key: app_kubernetes_io_name
    
    exporters:
      otlphttp/loki:
        endpoint: http://loki-loki-distributed-gateway.observability.svc.cluster.local:80/otlp
    
    service:
      pipelines:
        logs:
          receivers: [otlp, filelog]
          processors: [k8sattributes, batch, resource]
          exporters: [otlphttp/loki]
```

## Summary

| Question | Answer |
|----------|--------|
| **Default scope** | Captures **ALL pods** on the node (including system pods) |
| **Can it filter?** | ✅ **Yes, using include/exclude patterns** |
| **Filter by namespace?** | ✅ **Yes** - `include: [/var/log/pods/default_*_*/*.log]` |
| **Filter by pod name?** | ✅ **Yes** - `include: [/var/log/pods/*_dm-nkp-*_*/*.log]` |
| **Filter by labels?** | ⚠️ **Limited** - better to filter at receiver level |
| **Recommended approach** | Filter at **receiver level** using `include`/`exclude` patterns |

**Bottom line**:

- **Default**: Captures all pods (system + application)
- **With filtering**: Can capture only your app's pods using `include` patterns
- **Best practice**: Filter by namespace at receiver level for efficiency
