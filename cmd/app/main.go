package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/deepak-muley/dm-nkp-gitops-custom-app/internal/metrics"
	"github.com/deepak-muley/dm-nkp-gitops-custom-app/internal/server"
	"github.com/deepak-muley/dm-nkp-gitops-custom-app/internal/telemetry"
)

func main() {
	ctx := context.Background()
	port := getEnv("PORT", "8080")
	serviceName := getEnv("OTEL_SERVICE_NAME", "dm-nkp-gitops-custom-app")

	// Initialize OpenTelemetry telemetry (logging, tracing, metrics)
	// Note: Use log.Printf for initialization messages since logger isn't initialized yet
	log.Printf("[INFO] Initializing OpenTelemetry telemetry for service: %s", serviceName)
	log.Printf("[INFO] OTLP Endpoint: %s", getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317"))

	// Initialize logging first (simplest)
	if err := telemetry.InitializeLogger(); err != nil {
		log.Printf("[WARN] Failed to initialize logger: %v (continuing with stdout logging)", err)
	} else {
		log.Printf("[INFO] Logger initialized successfully")
		// Now we can use OTLP logger
		telemetry.LogInfo(ctx, fmt.Sprintf("OpenTelemetry telemetry initialization started for service: %s", serviceName))
		telemetry.LogInfo(ctx, fmt.Sprintf("OTLP Endpoint: %s", getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")))
		telemetry.LogInfo(ctx, "Logger initialized successfully")
	}

	// Initialize tracing
	if err := telemetry.InitializeTracer(); err != nil {
		log.Printf("[WARN] Failed to initialize tracer: %v (tracing disabled)", err)
		log.Printf("[INFO] Traces will not be exported, but instrumentation will continue")
		telemetry.LogWarn(ctx, fmt.Sprintf("Failed to initialize tracer: %v (tracing disabled)", err))
		telemetry.LogInfo(ctx, "Traces will not be exported, but instrumentation will continue")
	} else {
		log.Printf("[INFO] Tracer initialized successfully")
		telemetry.LogInfo(ctx, "Tracer initialized successfully")
	}

	// Initialize metrics (now returns error)
	if err := metrics.Initialize(); err != nil {
		log.Printf("[WARN] Failed to initialize metrics: %v", err)
		log.Printf("[INFO] Metrics will not be exported, but instrumentation will continue")
		log.Printf("[INFO] This is normal if OTel Collector is not available (e.g., in e2e tests)")
		telemetry.LogWarn(ctx, fmt.Sprintf("Failed to initialize metrics: %v", err))
		telemetry.LogInfo(ctx, "Metrics will not be exported, but instrumentation will continue")
		telemetry.LogInfo(ctx, "This is normal if OTel Collector is not available (e.g., in e2e tests)")
		// Don't fail - allow app to run without collector for testing
	} else {
		log.Printf("[INFO] Metrics initialized successfully")
		telemetry.LogInfo(ctx, "Metrics initialized successfully")
	}

	// Create HTTP server
	srv := server.New(port)

	// Start server in a goroutine
	go func() {
		serverCtx := context.Background()
		telemetry.LogInfo(serverCtx, fmt.Sprintf("Starting HTTP server on port %s", port))
		telemetry.LogInfo(serverCtx, "Server endpoints:")
		telemetry.LogInfo(serverCtx, fmt.Sprintf("  - Root: http://localhost:%s/", port))
		telemetry.LogInfo(serverCtx, fmt.Sprintf("  - Health: http://localhost:%s/health", port))
		telemetry.LogInfo(serverCtx, fmt.Sprintf("  - Ready: http://localhost:%s/ready", port))
		telemetry.LogInfo(serverCtx, "Telemetry data will be sent to OpenTelemetry Collector")
		if err := srv.Start(); err != nil && err != http.ErrServerClosed {
			telemetry.LogError(serverCtx, "Server failed to start", err)
			log.Fatalf("[FATAL] Server failed to start: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	telemetry.LogInfo(shutdownCtx, "Shutting down server...")

	// Shutdown server first
	telemetry.LogInfo(shutdownCtx, "Shutting down HTTP server...")
	if err := srv.Shutdown(shutdownCtx); err != nil {
		telemetry.LogError(shutdownCtx, "Error shutting down server", err)
	} else {
		telemetry.LogInfo(shutdownCtx, "HTTP server shutdown complete")
	}

	// Then shutdown telemetry components
	telemetry.LogInfo(shutdownCtx, "Shutting down telemetry components...")
	if err := metrics.Shutdown(shutdownCtx); err != nil {
		telemetry.LogWarn(shutdownCtx, fmt.Sprintf("Error shutting down metrics: %v", err))
	} else {
		telemetry.LogInfo(shutdownCtx, "Metrics shutdown complete")
	}
	if err := telemetry.ShutdownTracer(shutdownCtx); err != nil {
		telemetry.LogWarn(shutdownCtx, fmt.Sprintf("Error shutting down tracer: %v", err))
	} else {
		telemetry.LogInfo(shutdownCtx, "Tracer shutdown complete")
	}
	if err := telemetry.ShutdownLogger(shutdownCtx); err != nil {
		telemetry.LogWarn(shutdownCtx, fmt.Sprintf("Error shutting down logger: %v", err))
	} else {
		telemetry.LogInfo(shutdownCtx, "Logger shutdown complete")
	}

	telemetry.LogInfo(shutdownCtx, "Server exited gracefully")
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
