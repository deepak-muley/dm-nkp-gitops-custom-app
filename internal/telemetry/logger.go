package telemetry

import (
	"context"
	"log"
)

// InitializeLogger sets up structured logging
// For simplicity, we use standard Go log which is collected by the OpenTelemetry Collector
// The collector parses stdout/stderr and forwards logs to Loki
func InitializeLogger() error {
	log.Printf("OpenTelemetry logging initialized")
	log.Printf("Logs will be collected via stdout/stderr and forwarded to Loki by the collector")
	return nil
}

// ShutdownLogger gracefully shuts down the logger
func ShutdownLogger(ctx context.Context) error {
	log.Printf("Shutting down logger")
	return nil
}

// LogInfo logs an info message
func LogInfo(ctx context.Context, message string, attrs ...map[string]string) {
	// Use standard log which will be collected by the collector
	log.Printf("[INFO] %s", message)
}

// LogError logs an error message
func LogError(ctx context.Context, message string, err error, attrs ...map[string]string) {
	if err != nil {
		log.Printf("[ERROR] %s: %v", message, err)
	} else {
		log.Printf("[ERROR] %s", message)
	}
}
