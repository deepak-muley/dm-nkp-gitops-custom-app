# OpenTelemetry Quick Reference

Quick reference for standard OpenTelemetry practices used in this codebase.

## What is Standard?

### ✅ Standard Practices

| Practice | Why | Example |
|----------|-----|---------|
| **OTLP Protocol** | Industry standard, enables correlation | `otlploggrpc.New()` |
| **Resource Attributes** | Service identification | `semconv.ServiceName()` |
| **Semantic Conventions** | Standard attribute names | `log.level`, `http.method` |
| **Context Propagation** | Trace correlation | `ctx` parameter in log functions |
| **Batch Processing** | Efficiency | `sdklog.NewBatchProcessor()` |
| **Graceful Degradation** | Reliability | Fallback to stdout/stderr |
| **Global Providers** | Consistency | `global.SetLoggerProvider()` |

### ❌ Non-Standard Practices

| Practice | Why Avoid | Alternative |
|----------|-----------|-------------|
| **Direct Backend Export** | Bypasses collector, no correlation | Use OTel Collector |
| **Custom Attributes** | Inconsistent queries | Use semantic conventions |
| **No Resource Attributes** | Can't identify service | Include `service.name` |
| **Ignore Context** | Breaks trace correlation | Always pass `ctx` |
| **No Fallback** | Fails if OTLP unavailable | Graceful degradation |

## Code Patterns

### Standard Logger Initialization

```go
// Standard: Resource with semantic conventions
res, err := resource.New(ctx,
    resource.WithAttributes(
        semconv.ServiceName(serviceName),
        semconv.ServiceVersion("0.1.0"),
    ),
)

// Standard: OTLP exporter
logExporter, err := otlploggrpc.New(ctx,
    otlploggrpc.WithEndpoint(otlpEndpoint),
    otlploggrpc.WithInsecure(),
)

// Standard: Batch processor
loggerProvider = sdklog.NewLoggerProvider(
    sdklog.WithResource(res),
    sdklog.WithProcessor(
        sdklog.NewBatchProcessor(logExporter),
    ),
)

// Standard: Global provider
global.SetLoggerProvider(loggerProvider)
```

### Standard Logging Function

```go
// Standard: Always include context, stdout/stderr fallback, OTLP
func LogInfo(ctx context.Context, message string, attrs ...map[string]string) {
    // Standard: Always log to stdout/stderr
    log.Printf("[INFO] %s", message)
    
    // Standard: Send via OTLP if enabled
    if useOTLP && otlpLogger != nil {
        record := otellog.Record{}
        record.SetSeverity(otellog.SeverityInfo)
        record.SetSeverityText("INFO")
        record.SetBody(otellog.StringValue(message))
        record.SetTimestamp(time.Now())
        
        // Standard: Semantic convention attributes
        record.AddAttributes(
            otellog.String("log.level", "info"),
            otellog.String("log.message", message),
        )
        
        // Standard: Emit with context for trace correlation
        otlpLogger.Emit(ctx, record)
    }
}
```

## Semantic Conventions

### Standard Attribute Names

**Logs:**

- `log.level` - Log level (info, error, debug, warn)
- `log.message` - Log message
- `error` - Error message (for errors)

**Metrics:**

- `http.server.request.duration` - Request duration
- `http.server.request.count` - Request count

**Traces:**

- `http.method` - HTTP method
- `http.url` - HTTP URL
- `http.status_code` - HTTP status code

### Resource Attributes

**Required:**

- `service.name` - Service name

**Recommended:**

- `service.version` - Service version
- `service.instance.id` - Instance ID
- `deployment.environment` - Environment (dev, prod)

## Configuration

### Standard Environment Variables

```bash
# Required
OTEL_SERVICE_NAME=dm-nkp-gitops-custom-app
OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317

# Optional
OTEL_LOGS_ENABLED=true
OTEL_TRACES_ENABLED=true
OTEL_METRICS_ENABLED=true
```

### Standard Defaults

```go
serviceName := getEnv("OTEL_SERVICE_NAME", "dm-nkp-gitops-custom-app")
otlpEndpoint := getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")
```

## Architecture

### Standard Flow

```
Application
    ├─→ OTLP (gRPC) ──→ OTel Collector ──→ Backends
    └─→ stdout/stderr ──→ (Fallback)
```

### Standard Components

1. **Application**: Sends telemetry via OTLP
2. **OTel Collector**: Receives, processes, forwards
3. **Backends**: Prometheus (metrics), Loki (logs), Tempo (traces)

## Checklist

### ✅ Standard Implementation Checklist

- [ ] Uses OTLP protocol (not direct backend export)
- [ ] Includes resource attributes (`service.name`, `service.version`)
- [ ] Uses semantic convention attribute names
- [ ] Passes context for trace correlation
- [ ] Uses batch processor for efficiency
- [ ] Has graceful degradation (stdout/stderr fallback)
- [ ] Uses global providers for consistency
- [ ] Includes proper error handling
- [ ] Uses standard environment variables
- [ ] Follows semantic conventions for severity levels

## References

- **Full Guide**: [opentelemetry-standard-practices.md](opentelemetry-standard-practices.md)
- **Specification**: <https://opentelemetry.io/docs/specs/>
- **Semantic Conventions**: <https://opentelemetry.io/docs/specs/semconv/>
- **Go SDK**: <https://pkg.go.dev/go.opentelemetry.io/otel>
