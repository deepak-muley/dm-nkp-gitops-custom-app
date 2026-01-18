# Capturing stdout/stderr Logs with OpenTelemetry

## Overview

There are several ways to capture stdout/stderr logs and send them via OTLP to OpenTelemetry Collector. The approach depends on your deployment environment (Kubernetes vs traditional servers).

## Option 1: Log Bridge (Recommended for Applications)

Use a log bridge that intercepts stdout/stderr and sends logs via OTLP.

### How It Works

```
Application → stdout/stderr → Log Bridge → OTLP → OTel Collector
```

### Implementation Approaches

#### A. Use OpenTelemetry Log Bridge Library

Many languages have log bridge libraries that:

- Intercept stdout/stderr writes
- Convert to OTLP log records
- Send via OTLP to collector

**Example (Go):**

```go
import (
    "go.opentelemetry.io/contrib/bridges/stdlib"
    "go.opentelemetry.io/otel/log/global"
)

// Bridge standard library log to OTel
bridge := stdlib.NewBridge()
bridge.SetLoggerProvider(global.LoggerProvider())

// Now all log.Printf() calls go via OTLP
log.Printf("This goes via OTLP!")
```

#### B. Redirect stdout/stderr to OTel Logger

```go
// Redirect stdout/stderr to OTel logger
import (
    "os"
    "go.opentelemetry.io/otel/log/global"
)

// Create a writer that sends to OTel
otlpWriter := &OTLPWriter{logger: global.Logger("stdout")}
os.Stdout = otlpWriter
os.Stderr = otlpWriter
```

## Option 2: OTel Collector filelog Receiver (Kubernetes)

Use OTel Collector's `filelog` receiver to read log files and send via OTLP.

### How It Works

```
Application → stdout/stderr → Log File → OTel Collector (filelog) → Loki
```

### Configuration

**OTel Collector Config:**

```yaml
receivers:
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
```

**Kubernetes Deployment:**

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otel-collector-logs
spec:
  template:
    spec:
      containers:
      - name: otel-collector
        volumeMounts:
        - name: varlog
          mountPath: /var/log
          readOnly: true
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
```

### Limitations

- Requires access to container runtime log files
- Needs DaemonSet deployment
- Requires hostPath volume mounts
- Security concerns (access to host filesystem)

## Option 3: Sidecar Container (Kubernetes)

Use a sidecar container that tails stdout/stderr and sends via OTLP.

### How It Works

```
Application Pod
├─→ App Container (stdout/stderr)
└─→ Log Sidecar (tails logs → OTLP → Collector)
```

### Implementation

**Deployment with Sidecar:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-log-sidecar
spec:
  template:
    spec:
      containers:
      - name: app
        # Your application
      - name: log-sidecar
        image: otel/opentelemetry-collector-contrib:latest
        command:
          - /otelcol-contrib
          - --config=/etc/otel-collector-config/config.yaml
        volumeMounts:
        - name: shared-logs
          mountPath: /var/log/app
      volumes:
      - name: shared-logs
        emptyDir: {}
```

**Sidecar Config:**

```yaml
receivers:
  filelog:
    include:
      - /var/log/app/*.log
exporters:
  otlp:
    endpoint: otel-collector:4317
service:
  pipelines:
    logs:
      receivers: [filelog]
      exporters: [otlp]
```

## Option 4: Use Logging Library with OTLP Support

Modify application to use a logging library that supports OTLP natively.

### Example: Use slog with OTel Bridge

```go
import (
    "log/slog"
    "go.opentelemetry.io/contrib/bridges/slog"
    "go.opentelemetry.io/otel/log/global"
)

// Bridge slog to OTel
bridge := slogbridge.New(slogbridge.WithLoggerProvider(global.LoggerProvider()))

// Use slog instead of log.Printf
slog.Info("This goes via OTLP!")
```

## Recommended Approach for This Application

### Current Implementation

The application now supports **both methods simultaneously**:

1. **Direct OTLP** (preferred):

   ```go
   telemetry.LogInfo(ctx, "message")  // Goes via OTLP
   ```

2. **stdout/stderr** (backward compatible):

   ```go
   log.Printf("message")  // Goes to stdout/stderr
   ```

### To Capture stdout/stderr Logs

If you want to capture ALL stdout/stderr logs (including third-party libraries), you can:

#### Option A: Add Log Bridge (Recommended)

Update `internal/telemetry/logger.go` to bridge stdout/stderr:

```go
import (
    "go.opentelemetry.io/contrib/bridges/stdlib"
)

func InitializeLogger() error {
    // ... existing OTLP setup ...
    
    // Bridge standard library log to OTel
    bridge := stdlib.NewBridge()
    bridge.SetLoggerProvider(global.LoggerProvider())
    
    // Now all log.Printf() calls also go via OTLP
    return nil
}
```

#### Option B: Use OTel Collector filelog Receiver

Deploy OTel Collector as DaemonSet with filelog receiver to read container logs.

## Comparison

| Approach | Pros | Cons | Use Case |
|----------|------|------|----------|
| **Log Bridge** | ✅ No infrastructure changes<br>✅ Works in any environment<br>✅ Captures all stdout/stderr | ❌ Requires code changes<br>❌ May need library support | Applications you can modify |
| **filelog Receiver** | ✅ No code changes<br>✅ Works with unmodified apps | ❌ Requires DaemonSet<br>❌ Needs log file access<br>❌ Security concerns | Legacy/unmodifiable apps |
| **Sidecar** | ✅ No code changes<br>✅ Isolated from app | ❌ Extra container per pod<br>❌ Resource overhead | When you can't modify app |
| **Direct OTLP** | ✅ Standard approach<br>✅ Best performance<br>✅ No extra components | ❌ Requires code changes | Modern applications (recommended) |

## For Kubernetes Specifically

### Best Practice

1. **For new/modifiable applications**: Use OTLP directly (current implementation)
2. **For legacy applications**: Use OTel Collector DaemonSet with filelog receiver
3. **For mixed environments**: Use both (OTLP for new apps, filelog for legacy)

### OTel Collector DaemonSet Configuration

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector-logs
  namespace: observability
spec:
  mode: daemonset
  config:
    receivers:
      filelog:
        include:
          - /var/log/pods/**/*.log
        operators:
          - type: json_parser
            id: parser-json
    exporters:
      otlphttp/loki:
        endpoint: http://loki-gateway:80/otlp
    service:
      pipelines:
        logs:
          receivers: [filelog]
          processors: [batch]
          exporters: [otlphttp/loki]
```

## Summary

**To capture stdout/stderr logs with OTel:**

1. **Best**: Use OTLP directly (already implemented)
2. **Alternative**: Add log bridge to intercept stdout/stderr → OTLP
3. **For legacy apps**: Use OTel Collector filelog receiver (DaemonSet)

**Current application:**

- ✅ Already sends logs via OTLP (standard approach)
- ✅ Also logs to stdout/stderr (backward compatible)
- ✅ Can add log bridge if you want to capture ALL stdout/stderr
