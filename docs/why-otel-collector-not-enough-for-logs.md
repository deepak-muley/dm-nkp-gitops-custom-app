# Why OTel Collector Alone Isn't Enough for Logs

## Root Cause Analysis

### Current Situation

1. **Application Logging**: The app logs to stdout/stderr using standard Go `log.Printf()`
   - Location: `internal/telemetry/logger.go`
   - Method: Standard Go logging (stdout/stderr)

2. **OTel Collector Configuration**: Only has OTLP receiver
   - Receivers: `otlp` (gRPC and HTTP)
   - This receiver only accepts logs sent via **OTLP protocol**

3. **The Gap**:
   - ❌ App logs → stdout/stderr (not OTLP)
   - ❌ OTel Collector → OTLP receiver (only receives OTLP)
   - ❌ **No bridge between stdout/stderr and OTLP**

### Why OTel Collector Can't Collect stdout/stderr Logs

**OTel Collector receivers available:**

- `otlp` - Receives OTLP protocol (gRPC/HTTP)
- `filelog` - Reads log files from filesystem
- `syslog` - Receives syslog protocol
- `k8sattributes` - Adds Kubernetes metadata (processor, not receiver)

**The Problem:**

- `otlp` receiver: Requires app to send logs via OTLP (not happening)
- `filelog` receiver: Requires access to log files
  - In Kubernetes, pod logs are in container runtime, not filesystem
  - Would need complex volume mounts and log file access
  - Not practical for standard Kubernetes deployments

### Why Not Use filelog Receiver?

1. **Kubernetes Log Storage**: Pod logs are stored in container runtime (containerd/docker), not in pod filesystem
2. **Access Complexity**: Would require:
   - Mounting container runtime log directories
   - Running OTel Collector as DaemonSet with hostPath volumes
   - Complex security context configurations
   - Not scalable or maintainable

## Solution: Send Logs via OTLP

### Recommended Approach

**Modify the application to send logs via OpenTelemetry OTLP protocol** instead of stdout/stderr.

### Benefits

1. ✅ **No Additional Components**: OTel Collector already configured
2. ✅ **Standard Approach**: OpenTelemetry Logs SDK is the modern standard
3. ✅ **No EOL Products**: Uses current, maintained OpenTelemetry SDK
4. ✅ **Consistent**: Same approach as metrics and traces
5. ✅ **Works with Existing Setup**: OTel Collector already has OTLP receiver and Loki exporter

### Implementation

Use OpenTelemetry Logs SDK in Go:

```go
import (
    "go.opentelemetry.io/otel/log"
    "go.opentelemetry.io/otel/log/global"
    "go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
    "go.opentelemetry.io/otel/sdk/log"
    "go.opentelemetry.io/otel/sdk/resource"
)

// Initialize OTLP logger
func InitializeLogger() error {
    ctx := context.Background()
    
    // Create OTLP log exporter
    exporter, err := otlploggrpc.New(ctx,
        otlploggrpc.WithEndpoint(getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")),
        otlploggrpc.WithInsecure(),
    )
    if err != nil {
        return err
    }
    
    // Create logger provider
    loggerProvider := log.NewLoggerProvider(
        log.WithResource(resource.NewWithAttributes(...)),
        log.WithProcessor(log.NewBatchProcessor(exporter)),
    )
    
    global.SetLoggerProvider(loggerProvider)
    return nil
}
```

### Current vs Proposed

**Current (stdout/stderr):**

```
App → stdout/stderr → ❌ Nothing collects → ❌ No logs in Loki
```

**Proposed (OTLP):**

```
App → OTLP → OTel Collector → Loki → ✅ Logs visible in Grafana
```

## Alternative Solutions (Not Recommended)

### Option 1: Log Collection Agent (EOL/Deprecated)

- Grafana Agent Operator (deprecated chart)
- Fluent Bit (requires additional DaemonSet)
- **Issue**: Adds complexity, additional components, some are EOL

### Option 2: filelog Receiver (Complex)

- Requires DaemonSet deployment
- Requires hostPath volume mounts
- Complex security configurations
- **Issue**: Not practical, complex, security concerns

## Conclusion

**OTel Collector alone isn't enough because:**

- It only has OTLP receiver (for OTLP protocol logs)
- App logs to stdout/stderr (not OTLP protocol)
- No built-in bridge between stdout/stderr and OTLP

**Best Solution:**

- Modify application to send logs via OTLP using OpenTelemetry Logs SDK
- No additional components needed
- Uses current, maintained OpenTelemetry standards
- Works with existing OTel Collector configuration

## Next Steps

1. Update `internal/telemetry/logger.go` to use OpenTelemetry Logs SDK
2. Send logs via OTLP to OTel Collector
3. OTel Collector will forward to Loki (already configured)
4. Logs will appear in Grafana

This is the standard, modern approach recommended by OpenTelemetry.
