package server

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/deepak-muley/dm-nkp-gitops-custom-app/internal/metrics"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// shutdowner is an interface for shutting down servers (for testing)
type shutdowner interface {
	Shutdown(ctx context.Context) error
}

type Server struct {
	httpServer    *http.Server
	metricsServer *http.Server
	// test hooks for mocking (only set in tests)
	httpShutdowner    shutdowner
	metricsShutdowner shutdowner
}

func New(port, metricsPort string) *Server {
	mux := http.NewServeMux()
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/health", handleHealth)
	mux.HandleFunc("/ready", handleReady)

	metricsMux := http.NewServeMux()
	metricsMux.Handle("/metrics", promhttp.Handler())

	return &Server{
		httpServer: &http.Server{
			Addr:         fmt.Sprintf(":%s", port),
			Handler:      mux,
			ReadTimeout:  15 * time.Second,
			WriteTimeout: 15 * time.Second,
			IdleTimeout:  60 * time.Second,
		},
		metricsServer: &http.Server{
			Addr:         fmt.Sprintf(":%s", metricsPort),
			Handler:      metricsMux,
			ReadTimeout:  15 * time.Second,
			WriteTimeout: 15 * time.Second,
			IdleTimeout:  60 * time.Second,
		},
	}
}

func (s *Server) Start() error {
	// Start metrics server in a goroutine
	go func() {
		if err := s.metricsServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			fmt.Printf("Metrics server error: %v\n", err)
		}
	}()

	return s.httpServer.ListenAndServe()
}

func (s *Server) Shutdown(ctx context.Context) error {
	var err error
	
	// Use test hook if set, otherwise use real server
	var metricsShutdownErr error
	if s.metricsShutdowner != nil {
		metricsShutdownErr = s.metricsShutdowner.Shutdown(ctx)
	} else if s.metricsServer != nil {
		metricsShutdownErr = s.metricsServer.Shutdown(ctx)
	}
	err = metricsShutdownErr
	
	// Use test hook if set, otherwise use real server
	var httpShutdownErr error
	if s.httpShutdowner != nil {
		httpShutdownErr = s.httpShutdowner.Shutdown(ctx)
	} else if s.httpServer != nil {
		httpShutdownErr = s.httpServer.Shutdown(ctx)
	}
	
	if httpShutdownErr != nil {
		if err == nil {
			err = httpShutdownErr
		}
	}
	return err
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	metrics.IncrementRequestCounter()
	metrics.IncrementRequestCounterVec(r.Method, "200")
	metrics.UpdateActiveConnections(1)
	defer func() {
		metrics.UpdateRequestDuration(time.Since(start))
		metrics.UpdateActiveConnections(0)
		metrics.UpdateResponseSize(float64(len(`{"message": "Hello from dm-nkp-gitops-custom-app", "version": "0.1.0"}`)))
	}()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, `{"message": "Hello from dm-nkp-gitops-custom-app", "version": "0.1.0"}`)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, `{"status": "healthy"}`)
}

func handleReady(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, `{"status": "ready"}`)
}

