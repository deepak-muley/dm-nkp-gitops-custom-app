# OpenTelemetry Standard Practices

This document outlines the standard practices followed in this codebase for OpenTelemetry instrumentation, aligned with official OpenTelemetry specifications and best practices.

## Table of Contents

- [Overview](#overview)
- [Architecture Principles](#architecture-principles)
- [Logging Standards](#logging-standards)
- [Metrics Standards](#metrics-standards)
- [Tracing Standards](#tracing-standards)
- [Resource Attributes](#resource-attributes)
- [Semantic Conventions](#semantic-conventions)
- [Error Handling](#error-handling)
- [Configuration](#configuration)

## Overview

### What is Standard?

OpenTelemetry standards are defined by:

1. **OpenTelemetry Specification**: Official spec at [opentelemetry.io](https://opentelemetry.io/docs/specs/)
2. **Semantic Conventions**: Standard attribute names and values
3. **OTLP Protocol**: OpenTelemetry Protocol for data transmission
4. **SDK Best Practices**: Recommended patterns from official SDKs

### Why Follow Standards?

- ✅ **Interoperability**: Works with any OTel-compatible backend
- ✅ **Consistency**: Same patterns across all telemetry signals
- ✅ **Maintainability**: Easier to understand and maintain
- ✅ **Future-proof**: Aligned with industry standards

## Architecture Principles

### Standard Architecture

```
Application
    ├─→ OTLP (gRPC/HTTP) ──→ OTel Collector ──→ Backends (Prometheus, Loki, Tempo)
    └─→ stdout/stderr ──────→ (Optional: for backward compatibility)
```

### Key Principles

1. **OTLP First**: Use OTLP as the primary transport protocol
2. **Collector Pattern**: Always use OTel Collector (don't send directly to backends)
3. **Graceful Degradation**: Fallback to stdout/stderr if OTLP unavailable
4. **Resource Attributes**: Always include service identification
5. **Semantic Conventions**: Use standard attribute names

## Logging Standards

### Standard Practices

#### 1. Use OTLP for Production

**Standard**: Send logs via OTLP to OTel Collector

```go
// Standard: Use OTLP gRPC exporter
logExporter, err := otlploggrpc.New(ctx,
    otlploggrpc.WithEndpoint(otlpEndpoint),
    otlploggrpc.WithInsecure(), // Use TLS in production
)
```

**Why**: OTLP is the standard protocol, enables correlation with traces/metrics

#### 2. Always Include stdout/stderr Fallback

**Standard**: Always log to stdout/stderr for backward compatibility

```go
// Standard: Always log to stdout/stderr
log.Printf("[INFO] %s", message)

// Also send via OTLP if enabled
if useOTLP {
    otlpLogger.Emit(ctx, record)
}
```

**Why**: Ensures logs are available even if OTLP fails, supports local development

#### 3. Use Resource Attributes

**Standard**: Include service identification in resource

```go
res, err := resource.New(ctx,
    resource.WithAttributes(
        semconv.ServiceName(serviceName),
        semconv.ServiceVersion("0.1.0"),
    ),
)
```

**Why**: Enables filtering and correlation across telemetry signals

#### 4. Use Batch Processor

**Standard**: Use batch processor for efficiency

```go
loggerProvider = sdklog.NewLoggerProvider(
    sdklog.WithResource(res),
    sdklog.WithProcessor(
        sdklog.NewBatchProcessor(logExporter),
    ),
)
```

**Why**: Reduces network overhead, improves performance

#### 5. Use Context for Trace Correlation

**Standard**: Pass context to log functions for trace correlation

```go
func LogInfo(ctx context.Context, message string, attrs ...map[string]string) {
    // Context enables trace correlation
    currentLogger.Emit(ctx, record)
}
```

**Why**: Enables correlation between logs and traces

#### 6. Use Semantic Convention Attributes

**Standard**: Use standard attribute names

```go
record.AddAttributes(
    otellog.String("log.level", "info"),
    otellog.String("log.message", message),
)
```

**Why**: Ensures consistency and enables standard queries

#### 7. Use Proper Severity Levels

**Standard**: Use standard severity levels

```go
record.SetSeverity(otellog.SeverityInfo)
record.SetSeverityText("INFO")
```

**Why**: Enables filtering and alerting based on severity

### Non-Standard Practices to Avoid

❌ **Don't**: Send logs directly to backends (bypass OTel Collector)
❌ **Don't**: Use non-standard attribute names
❌ **Don't**: Skip resource attributes
❌ **Don't**: Ignore context (breaks trace correlation)
❌ **Don't**: Use custom severity levels

## Metrics Standards

### Standard Practices

#### 1. Use OTLP for Metrics

**Standard**: Send metrics via OTLP to OTel Collector

```go
metricExporter, err := otlpmetricgrpc.New(ctx,
    otlpmetricgrpc.WithEndpoint(otlpEndpoint),
    otlpmetricgrpc.WithInsecure(),
)
```

**Why**: Standard protocol, enables correlation

#### 2. Use Semantic Convention Names

**Standard**: Use standard metric names

```go
// Standard: Use semantic convention names
meter.Int64Counter(
    "http.server.request.duration",
    metric.WithDescription("HTTP server request duration"),
    metric.WithUnit("ms"),
)
```

**Why**: Ensures consistency and standard queries

#### 3. Include Resource Attributes

**Standard**: Include service identification

```go
res, err := resource.New(ctx,
    resource.WithAttributes(
        semconv.ServiceName(serviceName),
        semconv.ServiceVersion("0.1.0"),
    ),
)
```

**Why**: Enables filtering and correlation

### Non-Standard Practices to Avoid

❌ **Don't**: Use non-standard metric names
❌ **Don't**: Skip resource attributes
❌ **Don't**: Use custom units

## Tracing Standards

### Standard Practices

#### 1. Use OTLP for Traces

**Standard**: Send traces via OTLP to OTel Collector

```go
traceExporter, err := otlptracegrpc.New(ctx,
    otlptracegrpc.WithEndpoint(otlpEndpoint),
    otlptracegrpc.WithInsecure(),
)
```

**Why**: Standard protocol, enables correlation

#### 2. Use Semantic Convention Attributes

**Standard**: Use standard span attribute names

```go
span.SetAttributes(
    attribute.String("http.method", r.Method),
    attribute.String("http.url", r.URL.String()),
    attribute.String("http.route", "/"),
)
```

**Why**: Ensures consistency and standard queries

#### 3. Use Proper Sampling

**Standard**: Use appropriate sampling strategy

```go
tracerProvider = sdktrace.NewTracerProvider(
    sdktrace.WithSampler(sdktrace.AlwaysSample()), // Or use other strategies
)
```

**Why**: Balances observability with performance

#### 4. Use Context Propagation

**Standard**: Use context for trace propagation

```go
ctx, span := tracer.Start(ctx, "operation.name")
defer span.End()
```

**Why**: Enables distributed tracing

### Non-Standard Practices to Avoid

❌ **Don't**: Use non-standard attribute names
❌ **Don't**: Skip context propagation
❌ **Don't**: Use custom span names

## Resource Attributes

### Standard Resource Attributes

**Standard**: Always include these attributes:

```go
resource.WithAttributes(
    semconv.ServiceName(serviceName),        // Required
    semconv.ServiceVersion("0.1.0"),          // Recommended
    semconv.ServiceInstanceID(instanceID),   // Optional
    semconv.DeploymentEnvironment("production"), // Optional
)
```

**Why**: Enables filtering, correlation, and service identification

### Semantic Conventions

**Standard**: Use semantic convention attribute names from:

- `go.opentelemetry.io/otel/semconv/v1.32.0`

**Why**: Ensures consistency across all telemetry signals

## Semantic Conventions

### Standard Attribute Names

**Standard**: Use semantic convention attribute names:

- **Logs**: `log.level`, `log.message`, `error`
- **Metrics**: `http.server.request.duration`, `http.server.request.count`
- **Traces**: `http.method`, `http.url`, `http.status_code`

**Why**: Enables standard queries and filtering

### Where to Find Conventions

- **Logs**: [Log Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/general/logs/)
- **Metrics**: [Metric Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/general/metrics/)
- **Traces**: [Trace Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/general/tracing/)

## Error Handling

### Standard Practices

#### 1. Graceful Degradation

**Standard**: Don't fail if OTLP unavailable

```go
if err := initializeOTLPLogger(ctx, otlpEndpoint, serviceName); err != nil {
    log.Printf("[WARN] Failed to initialize OTLP logger: %v (continuing with stdout/stderr only)", err)
    // Continue with stdout/stderr only
}
```

**Why**: Ensures application continues to work even if telemetry fails

#### 2. Use Context Timeouts

**Standard**: Use context with timeout for shutdown

```go
shutdownCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()
if err := loggerProvider.Shutdown(shutdownCtx); err != nil {
    // Handle error
}
```

**Why**: Prevents hanging during shutdown

#### 3. Log Errors Appropriately

**Standard**: Log errors with proper severity

```go
log.Printf("[ERROR] Failed to initialize OTLP logger: %v", err)
```

**Why**: Ensures errors are visible and actionable

## Configuration

### Standard Environment Variables

**Standard**: Use standard environment variable names:

```bash
# Required
OTEL_SERVICE_NAME=dm-nkp-gitops-custom-app
OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317

# Optional
OTEL_LOGS_ENABLED=true
OTEL_TRACES_ENABLED=true
OTEL_METRICS_ENABLED=true
```

**Why**: Ensures consistency and compatibility

### Standard Configuration Pattern

**Standard**: Use environment variables with sensible defaults

```go
serviceName := getEnv("OTEL_SERVICE_NAME", "dm-nkp-gitops-custom-app")
otlpEndpoint := getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")
```

**Why**: Enables easy configuration without code changes

## Summary

### What Makes Code Standard?

✅ **Uses OTLP protocol** for all telemetry
✅ **Includes resource attributes** (service.name, service.version)
✅ **Uses semantic conventions** for attribute names
✅ **Graceful degradation** if OTLP unavailable
✅ **Context propagation** for trace correlation
✅ **Batch processing** for efficiency
✅ **Standard environment variables** for configuration

### What Makes Code Non-Standard?

❌ **Bypasses OTel Collector** (sends directly to backends)
❌ **Uses custom attribute names** (not semantic conventions)
❌ **Skips resource attributes** (no service identification)
❌ **Ignores context** (breaks trace correlation)
❌ **No graceful degradation** (fails if OTLP unavailable)

## References

- [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/)
- [Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- [Go SDK Documentation](https://pkg.go.dev/go.opentelemetry.io/otel)
- [Best Practices Guide](https://opentelemetry.io/docs/specs/otel/)
