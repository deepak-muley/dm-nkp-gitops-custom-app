# Implementation Guide: Capturing stdout/stderr with OTel

## Quick Answer

To capture **ALL** stdout/stderr logs (including from third-party libraries) and send them via OTLP:

### Option 1: Custom Writer Bridge (Recommended for Complete Coverage)

Create a custom `io.Writer` that intercepts stdout/stderr and sends logs via OTLP:

**Step 1:** Update `internal/telemetry/logger.go`:

```go
import (
    "io"
    "os"
    // ... other imports
)

type otlpWriter struct {
    logger otellog.Logger
    ctx    context.Context
    level  otellog.Severity
}

func (w *otlpWriter) Write(p []byte) (n int, err error) {
    if w.logger != nil {
        record := otellog.Record{}
        record.SetSeverity(w.level)
        record.SetSeverityText("INFO")
        record.SetBody(otellog.StringValue(string(p)))
        record.SetTimestamp(time.Now())
        w.logger.Emit(w.ctx, record)
    }
    return len(p), nil
}

func enableLogBridge(ctx context.Context) error {
    mu.RLock()
    currentLogger := otlpLogger
    useOTLPFlag := useOTLP
    mu.RUnlock()
    
    if !useOTLPFlag || currentLogger == nil {
        return fmt.Errorf("OTLP logger not initialized")
    }
    
    // Redirect stdout to OTLP writer
    otlpStdout := &otlpWriter{
        logger: currentLogger,
        ctx:    ctx,
        level:  otellog.SeverityInfo,
    }
    os.Stdout = io.MultiWriter(os.Stdout, otlpStdout)
    
    // Redirect stderr to OTLP writer
    otlpStderr := &otlpWriter{
        logger: currentLogger,
        ctx:    ctx,
        level:  otellog.SeverityError,
    }
    os.Stderr = io.MultiWriter(os.Stderr, otlpStderr)
    
    log.Printf("[INFO] Log bridge enabled - all stdout/stderr logs will be sent via OTLP")
    return nil
}
```

**Result:** All stdout/stderr output (including from third-party libraries) will be sent via OTLP.

### Option 2: Use OTel Collector filelog Receiver (No Code Changes)

Deploy OTel Collector as DaemonSet to read container logs:

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

**Note:** Requires DaemonSet deployment and access to container runtime log files.

## Current Implementation

### What We Have Now

✅ **Direct OTLP logging** (via `telemetry.LogInfo()`, etc.)

- Sends logs directly via OTLP
- Standard approach
- Works perfectly

✅ **stdout/stderr logging** (via `log.Printf()`)

- Backward compatible
- Works for local development
- Currently NOT captured by OTLP (only goes to stdout/stderr)

### What's Missing (If You Want Complete Coverage)

❌ **Logs from third-party libraries** that use `log.Printf()`

- These currently only go to stdout/stderr
- Not captured by OTLP unless you add a log bridge

## Comparison

| Approach | Captures | Code Changes | Infrastructure |
|----------|----------|--------------|----------------|
| **Current (Direct OTLP)** | Only `telemetry.Log*()` calls | ✅ Already done | None |
| **Log Bridge** | ALL `log.Printf()` calls | ✅ Small change | None |
| **filelog Receiver** | ALL stdout/stderr | ❌ None | DaemonSet required |

## Recommendation

**For this application:**

1. **Keep current implementation** (direct OTLP via `telemetry.Log*()`)
   - Standard approach
   - Already working
   - Good performance

2. **Add log bridge** (if you need to capture third-party library logs)
   - Small code change
   - Captures everything
   - No infrastructure changes

3. **Use filelog receiver** (only if you can't modify the application)
   - No code changes
   - Requires DaemonSet
   - More complex setup

## Example: Adding Log Bridge

See `internal/telemetry/logger_bridge_example.go` for a complete example.

The code is already prepared in `logger.go` - just uncomment the relevant sections.
