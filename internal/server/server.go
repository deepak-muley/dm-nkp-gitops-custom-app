package server

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/deepak-muley/dm-nkp-gitops-custom-app/internal/metrics"
	"github.com/deepak-muley/dm-nkp-gitops-custom-app/internal/telemetry"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// shutdowner is an interface for shutting down servers (for testing)
type shutdowner interface {
	Shutdown(ctx context.Context) error
}

type Server struct {
	httpServer *http.Server
	// test hooks for mocking (only set in tests)
	httpShutdowner shutdowner
}

func New(port string) *Server {
	mux := http.NewServeMux()
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/health", handleHealth)
	mux.HandleFunc("/ready", handleReady)

	// Wrap handler with OpenTelemetry HTTP instrumentation
	otelHandler := otelhttp.NewHandler(
		mux,
		"http-server",
		otelhttp.WithSpanNameFormatter(func(operation string, r *http.Request) string {
			return fmt.Sprintf("%s %s", r.Method, r.URL.Path)
		}),
	)

	return &Server{
		httpServer: &http.Server{
			Addr:         fmt.Sprintf(":%s", port),
			Handler:      otelHandler,
			ReadTimeout:  15 * time.Second,
			WriteTimeout: 15 * time.Second,
			IdleTimeout:  60 * time.Second,
		},
	}
}

func (s *Server) Start() error {
	return s.httpServer.ListenAndServe()
}

func (s *Server) Shutdown(ctx context.Context) error {
	// Use test hook if set, otherwise use real server
	if s.httpShutdowner != nil {
		return s.httpShutdowner.Shutdown(ctx)
	}
	if s.httpServer != nil {
		return s.httpServer.Shutdown(ctx)
	}
	return nil
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	ctx := r.Context()
	
	// Get span from context for tracing
	span := trace.SpanFromContext(ctx)
	tracer := otel.Tracer("dm-nkp-gitops-custom-app/server")
	
	// Create a child span for processing
	ctx, processSpan := tracer.Start(ctx, "process.request")
	defer processSpan.End()
	
	if span.IsRecording() {
		span.SetAttributes(
			attribute.String("http.method", r.Method),
			attribute.String("http.url", r.URL.String()),
			attribute.String("http.route", "/"),
			attribute.String("user_agent", r.UserAgent()),
			attribute.String("http.client_ip", r.RemoteAddr),
		)
		processSpan.SetAttributes(
			attribute.String("operation", "root_handler"),
			attribute.String("handler.type", "root"),
		)
	}
	
	// Log request with structured logging
	telemetry.LogInfo(ctx, fmt.Sprintf("Received request: method=%s path=%s remote_addr=%s", 
		r.Method, r.URL.Path, r.RemoteAddr))
	
	// Update metrics
	metrics.IncrementRequestCounter()
	metrics.IncrementRequestCounterVec(r.Method, "200")
	metrics.UpdateActiveConnections(1)
	
	// Simulate some business logic with a trace span
	ctx, businessSpan := tracer.Start(ctx, "business.logic")
	businessSpan.SetAttributes(attribute.String("business.operation", "generate_response"))
	telemetry.LogInfo(ctx, "Processing business logic for root endpoint")
	
	// Simulate processing time
	time.Sleep(10 * time.Millisecond)
	
	businessSpan.End()
	
	responseBody := `{"message": "Hello from dm-nkp-gitops-custom-app", "version": "0.1.0"}`
	
	defer func() {
		duration := time.Since(start)
		metrics.UpdateRequestDuration(duration)
		metrics.UpdateActiveConnections(0)
		metrics.UpdateResponseSize(float64(len(responseBody)))
		
		// Add span attributes with timing information
		if span.IsRecording() {
			span.SetAttributes(
				attribute.Int("http.status_code", http.StatusOK),
				attribute.Int64("http.response.size", int64(len(responseBody))),
				attribute.Float64("http.request.duration_ms", float64(duration.Nanoseconds())/1e6),
				attribute.Bool("http.request.success", true),
			)
			processSpan.SetAttributes(
				attribute.Float64("processing.duration_ms", float64(duration.Nanoseconds())/1e6),
			)
		}
		
		// Log completion with structured information
		telemetry.LogInfo(ctx, fmt.Sprintf("Request completed: status=%d duration_ms=%.2f response_size=%d",
			http.StatusOK, float64(duration.Nanoseconds())/1e6, len(responseBody)))
	}()
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = fmt.Fprint(w, responseBody)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	span := trace.SpanFromContext(ctx)
	tracer := otel.Tracer("dm-nkp-gitops-custom-app/server")
	
	ctx, healthSpan := tracer.Start(ctx, "health.check")
	defer healthSpan.End()
	
	if span.IsRecording() {
		span.SetAttributes(
			attribute.String("http.method", r.Method),
			attribute.String("http.url", r.URL.String()),
			attribute.String("health.check.type", "liveness"),
		)
		healthSpan.SetAttributes(
			attribute.String("check.type", "liveness"),
			attribute.String("endpoint", "/health"),
		)
	}
	
	// Log health check with structured logging
	telemetry.LogInfo(ctx, "Health check requested: type=liveness")
	
	// Perform health checks (simulate)
	ctx, checkSpan := tracer.Start(ctx, "health.checks.run")
	checkSpan.SetAttributes(
		attribute.String("check.component", "application"),
		attribute.Bool("check.status", true),
	)
	telemetry.LogInfo(ctx, "Running health checks: component=application status=healthy")
	time.Sleep(5 * time.Millisecond) // Simulate check time
	checkSpan.End()
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = fmt.Fprint(w, `{"status": "healthy"}`)
	
	telemetry.LogInfo(ctx, "Health check completed: status=healthy")
}

func handleReady(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	span := trace.SpanFromContext(ctx)
	tracer := otel.Tracer("dm-nkp-gitops-custom-app/server")
	
	ctx, readySpan := tracer.Start(ctx, "readiness.check")
	defer readySpan.End()
	
	if span.IsRecording() {
		span.SetAttributes(
			attribute.String("http.method", r.Method),
			attribute.String("http.url", r.URL.String()),
			attribute.String("health.check.type", "readiness"),
		)
		readySpan.SetAttributes(
			attribute.String("check.type", "readiness"),
			attribute.String("endpoint", "/ready"),
		)
	}
	
	// Log readiness check with structured logging
	telemetry.LogInfo(ctx, "Readiness check requested: type=readiness")
	
	// Perform readiness checks (simulate)
	ctx, checkSpan := tracer.Start(ctx, "readiness.checks.run")
	checkSpan.SetAttributes(
		attribute.String("check.component", "metrics"),
		attribute.Bool("check.status", true),
	)
	telemetry.LogInfo(ctx, "Running readiness checks: component=metrics status=ready")
	time.Sleep(5 * time.Millisecond) // Simulate check time
	checkSpan.End()
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = fmt.Fprint(w, `{"status": "ready"}`)
	
	telemetry.LogInfo(ctx, "Readiness check completed: status=ready")
}
