package main

import (
	"context"
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
	port := getEnv("PORT", "8080")
	serviceName := getEnv("OTEL_SERVICE_NAME", "dm-nkp-gitops-custom-app")

	// Initialize OpenTelemetry telemetry (logging, tracing, metrics)
	log.Printf("[INFO] Initializing OpenTelemetry telemetry for service: %s", serviceName)
	log.Printf("[INFO] OTLP Endpoint: %s", getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317"))
	
	// Initialize logging first (simplest)
	if err := telemetry.InitializeLogger(); err != nil {
		log.Printf("[WARN] Failed to initialize logger: %v (continuing with stdout logging)", err)
	} else {
		log.Printf("[INFO] Logger initialized successfully")
	}
	
	// Initialize tracing
	if err := telemetry.InitializeTracer(); err != nil {
		log.Printf("[WARN] Failed to initialize tracer: %v (tracing disabled)", err)
		log.Printf("[INFO] Traces will not be exported, but instrumentation will continue")
	} else {
		log.Printf("[INFO] Tracer initialized successfully")
	}
	
	// Initialize metrics (now returns error)
	if err := metrics.Initialize(); err != nil {
		log.Printf("[WARN] Failed to initialize metrics: %v", err)
		log.Printf("[INFO] Metrics will not be exported, but instrumentation will continue")
		log.Printf("[INFO] This is normal if OTel Collector is not available (e.g., in e2e tests)")
		// Don't fail - allow app to run without collector for testing
	} else {
		log.Printf("[INFO] Metrics initialized successfully")
	}

	// Create HTTP server
	srv := server.New(port)

	// Start server in a goroutine
	go func() {
		log.Printf("[INFO] Starting HTTP server on port %s", port)
		log.Printf("[INFO] Server endpoints:")
		log.Printf("[INFO]   - Root: http://localhost:%s/", port)
		log.Printf("[INFO]   - Health: http://localhost:%s/health", port)
		log.Printf("[INFO]   - Ready: http://localhost:%s/ready", port)
		log.Printf("[INFO] Telemetry data will be sent to OpenTelemetry Collector")
		if err := srv.Start(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[FATAL] Server failed to start: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("[INFO] Shutting down server...")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Shutdown server first
	log.Println("[INFO] Shutting down HTTP server...")
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("[ERROR] Error shutting down server: %v", err)
	} else {
		log.Println("[INFO] HTTP server shutdown complete")
	}

	// Then shutdown telemetry components
	log.Println("[INFO] Shutting down telemetry components...")
	if err := metrics.Shutdown(shutdownCtx); err != nil {
		log.Printf("[WARN] Error shutting down metrics: %v", err)
	} else {
		log.Println("[INFO] Metrics shutdown complete")
	}
	if err := telemetry.ShutdownTracer(shutdownCtx); err != nil {
		log.Printf("[WARN] Error shutting down tracer: %v", err)
	} else {
		log.Println("[INFO] Tracer shutdown complete")
	}
	if err := telemetry.ShutdownLogger(shutdownCtx); err != nil {
		log.Printf("[WARN] Error shutting down logger: %v", err)
	} else {
		log.Println("[INFO] Logger shutdown complete")
	}

	log.Println("[INFO] Server exited gracefully")
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
