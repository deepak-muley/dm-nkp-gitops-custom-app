package telemetry

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
	otellog "go.opentelemetry.io/otel/log"
	"go.opentelemetry.io/otel/log/global"
	sdklog "go.opentelemetry.io/otel/sdk/log"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.32.0"
)

var (
	loggerProvider *sdklog.LoggerProvider
	otlpLogger     otellog.Logger
	useOTLP        bool
	mu             sync.RWMutex
)

// InitializeLogger sets up structured logging following OpenTelemetry standards.
// Standard practice: Use OTLP for production, stdout/stderr for backward compatibility.
// - stdout/stderr: Standard Go logging (for backward compatibility and local development)
// - OTLP: OpenTelemetry logs sent directly to collector (standard approach for production)
func InitializeLogger() error {
	ctx := context.Background()
	serviceName := getEnv("OTEL_SERVICE_NAME", "dm-nkp-gitops-custom-app")
	otlpEndpoint := getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")

	// Always log to stdout/stderr for backward compatibility (standard practice)
	log.Printf("[INFO] OpenTelemetry logging initialized")
	log.Printf("[INFO] Logs will be sent via stdout/stderr (standard Go logging)")

	// Try to initialize OTLP logger (optional - won't fail if unavailable)
	// Standard practice: Graceful degradation if OTLP unavailable
	otlpEnabled := getEnv("OTEL_LOGS_ENABLED", "true")
	if otlpEnabled == "true" {
		if err := initializeOTLPLogger(ctx, otlpEndpoint, serviceName); err != nil {
			log.Printf("[WARN] Failed to initialize OTLP logger: %v (continuing with stdout/stderr only)", err)
			log.Printf("[INFO] OTLP logging disabled, using stdout/stderr only")
			mu.Lock()
			useOTLP = false
			mu.Unlock()
		} else {
			log.Printf("[INFO] OTLP logging enabled - logs will be sent to: %s", otlpEndpoint)
			mu.Lock()
			useOTLP = true
			mu.Unlock()
		}
	} else {
		log.Printf("[INFO] OTLP logging disabled via OTEL_LOGS_ENABLED=false")
		mu.Lock()
		useOTLP = false
		mu.Unlock()
	}

	return nil
}

// initializeOTLPLogger sets up OpenTelemetry OTLP logging following standard practices.
// Standard practices:
// 1. Use resource attributes (service.name, service.version) - semantic conventions
// 2. Use batch processor for efficiency
// 3. Use global logger provider for consistency
// 4. Create logger with instrumentation scope name
func initializeOTLPLogger(ctx context.Context, otlpEndpoint, serviceName string) error {
	// Standard practice: Create resource with semantic convention attributes
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
			semconv.ServiceVersion("0.1.0"),
		),
	)
	if err != nil {
		return fmt.Errorf("failed to create resource: %w", err)
	}

	// Standard practice: Use OTLP gRPC exporter for logs
	logExporter, err := otlploggrpc.New(ctx,
		otlploggrpc.WithEndpoint(otlpEndpoint),
		otlploggrpc.WithInsecure(), // Standard: Use TLS in production
	)
	if err != nil {
		return fmt.Errorf("failed to create log exporter: %w", err)
	}

	// Standard practice: Use batch processor for efficiency
	loggerProvider = sdklog.NewLoggerProvider(
		sdklog.WithResource(res),
		sdklog.WithProcessor(
			sdklog.NewBatchProcessor(logExporter),
		),
	)

	// Standard practice: Set global logger provider for consistency
	global.SetLoggerProvider(loggerProvider)

	// Standard practice: Create logger with instrumentation scope name
	otlpLogger = global.Logger("dm-nkp-gitops-custom-app/logs")

	return nil
}

// ShutdownLogger gracefully shuts down the logger following standard practices.
// Standard practice: Use context with timeout for graceful shutdown
func ShutdownLogger(ctx context.Context) error {
	mu.Lock()
	defer mu.Unlock()

	// Always log shutdown to stdout (standard practice)
	log.Printf("[INFO] Shutting down logger")

	// Standard practice: Shutdown with timeout to prevent hanging
	if loggerProvider != nil {
		shutdownCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		defer cancel()
		if err := loggerProvider.Shutdown(shutdownCtx); err != nil {
			log.Printf("[ERROR] Failed to shutdown OTLP logger: %v", err)
			return err
		}
		log.Printf("[INFO] OTLP logger shut down successfully")
	}

	return nil
}

// LogInfo logs an info message following OpenTelemetry standards.
// Standard practices:
// 1. Always log to stdout/stderr for backward compatibility
// 2. Send via OTLP if enabled
// 3. Use context for trace correlation
// 4. Include semantic convention attributes
func LogInfo(ctx context.Context, message string, attrs ...map[string]string) {
	// Standard practice: Always log to stdout/stderr (backward compatibility)
	log.Printf("[INFO] %s", message)

	// Standard practice: Send via OTLP if enabled
	mu.RLock()
	useOTLPFlag := useOTLP
	currentLogger := otlpLogger
	mu.RUnlock()

	if useOTLPFlag && currentLogger != nil {
		// Standard practice: Create log record with proper structure
		record := otellog.Record{}
		record.SetSeverity(otellog.SeverityInfo)
		record.SetSeverityText("INFO")
		record.SetBody(otellog.StringValue(message))
		record.SetTimestamp(time.Now())

		// Standard practice: Add custom attributes
		if len(attrs) > 0 {
			for k, v := range attrs[0] {
				record.AddAttributes(otellog.String(k, v))
			}
		}

		// Standard practice: Add semantic convention attributes
		record.AddAttributes(
			otellog.String("log.level", "info"),
			otellog.String("log.message", message),
		)

		// Standard practice: Emit log record with context for trace correlation
		currentLogger.Emit(ctx, record)
	}
}

// LogError logs an error message following OpenTelemetry standards.
// Standard practices:
// 1. Always log to stdout/stderr for backward compatibility
// 2. Send via OTLP if enabled
// 3. Include error details as attributes
// 4. Use ERROR severity level
func LogError(ctx context.Context, message string, err error, attrs ...map[string]string) {
	// Standard practice: Always log to stdout/stderr (backward compatibility)
	if err != nil {
		log.Printf("[ERROR] %s: %v", message, err)
	} else {
		log.Printf("[ERROR] %s", message)
	}

	// Standard practice: Send via OTLP if enabled
	mu.RLock()
	useOTLPFlag := useOTLP
	currentLogger := otlpLogger
	mu.RUnlock()

	if useOTLPFlag && currentLogger != nil {
		// Standard practice: Create log record with ERROR severity
		record := otellog.Record{}
		record.SetSeverity(otellog.SeverityError)
		record.SetSeverityText("ERROR")
		record.SetBody(otellog.StringValue(message))
		record.SetTimestamp(time.Now())

		// Standard practice: Add custom attributes
		if len(attrs) > 0 {
			for k, v := range attrs[0] {
				record.AddAttributes(otellog.String(k, v))
			}
		}

		// Standard practice: Add semantic convention attributes
		record.AddAttributes(
			otellog.String("log.level", "error"),
			otellog.String("log.message", message),
		)

		// Standard practice: Include error details as attribute
		if err != nil {
			record.AddAttributes(otellog.String("error", err.Error()))
		}

		// Standard practice: Emit log record with context for trace correlation
		currentLogger.Emit(ctx, record)
	}
}

// LogDebug logs a debug message following OpenTelemetry standards.
// Standard practices:
// 1. Always log to stdout/stderr for backward compatibility
// 2. Send via OTLP if enabled
// 3. Use DEBUG severity level
func LogDebug(ctx context.Context, message string, attrs ...map[string]string) {
	// Standard practice: Always log to stdout/stderr (backward compatibility)
	log.Printf("[DEBUG] %s", message)

	// Standard practice: Send via OTLP if enabled
	mu.RLock()
	useOTLPFlag := useOTLP
	currentLogger := otlpLogger
	mu.RUnlock()

	if useOTLPFlag && currentLogger != nil {
		// Standard practice: Create log record with DEBUG severity
		record := otellog.Record{}
		record.SetSeverity(otellog.SeverityDebug)
		record.SetSeverityText("DEBUG")
		record.SetBody(otellog.StringValue(message))
		record.SetTimestamp(time.Now())

		// Standard practice: Add custom attributes
		if len(attrs) > 0 {
			for k, v := range attrs[0] {
				record.AddAttributes(otellog.String(k, v))
			}
		}

		// Standard practice: Add semantic convention attributes
		record.AddAttributes(
			otellog.String("log.level", "debug"),
			otellog.String("log.message", message),
		)

		// Standard practice: Emit log record with context for trace correlation
		currentLogger.Emit(ctx, record)
	}
}

// LogWarn logs a warning message following OpenTelemetry standards.
// Standard practices:
// 1. Always log to stdout/stderr for backward compatibility
// 2. Send via OTLP if enabled
// 3. Use WARN severity level
func LogWarn(ctx context.Context, message string, attrs ...map[string]string) {
	// Standard practice: Always log to stdout/stderr (backward compatibility)
	log.Printf("[WARN] %s", message)

	// Standard practice: Send via OTLP if enabled
	mu.RLock()
	useOTLPFlag := useOTLP
	currentLogger := otlpLogger
	mu.RUnlock()

	if useOTLPFlag && currentLogger != nil {
		// Standard practice: Create log record with WARN severity
		record := otellog.Record{}
		record.SetSeverity(otellog.SeverityWarn)
		record.SetSeverityText("WARN")
		record.SetBody(otellog.StringValue(message))
		record.SetTimestamp(time.Now())

		// Standard practice: Add custom attributes
		if len(attrs) > 0 {
			for k, v := range attrs[0] {
				record.AddAttributes(otellog.String(k, v))
			}
		}

		// Standard practice: Add semantic convention attributes
		record.AddAttributes(
			otellog.String("log.level", "warn"),
			otellog.String("log.message", message),
		)

		// Standard practice: Emit log record with context for trace correlation
		currentLogger.Emit(ctx, record)
	}
}
