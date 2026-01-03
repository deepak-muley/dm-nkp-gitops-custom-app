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
)

func main() {
	port := getEnv("PORT", "8080")
	metricsPort := getEnv("METRICS_PORT", "9090")

	// Initialize metrics
	metrics.Initialize()

	// Create HTTP server
	srv := server.New(port, metricsPort)

	// Start server in a goroutine
	go func() {
		log.Printf("Starting server on port %s", port)
		log.Printf("Metrics endpoint available on port %s at /metrics", metricsPort)
		if err := srv.Start(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed to start: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited")
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
