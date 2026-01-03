package metrics

import (
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	// Counter: Total number of HTTP requests
	RequestCounter = promauto.NewCounter(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Total number of HTTP requests",
	})

	// Gauge: Current number of active connections
	ActiveConnections = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "http_active_connections",
		Help: "Current number of active HTTP connections",
	})

	// Histogram: Request duration in seconds
	RequestDuration = promauto.NewHistogram(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "HTTP request duration in seconds",
		Buckets: prometheus.DefBuckets,
	})

	// Summary: Response size in bytes
	ResponseSize = promauto.NewSummary(prometheus.SummaryOpts{
		Name:       "http_response_size_bytes",
		Help:       "HTTP response size in bytes",
		Objectives: map[float64]float64{0.5: 0.05, 0.9: 0.01, 0.99: 0.001},
	})

	// CounterVec: Requests by method and status
	RequestCounterVec = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_by_method_total",
			Help: "Total number of HTTP requests by method",
		},
		[]string{"method", "status"},
	)

	// GaugeVec: Custom business metric
	BusinessMetric = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "business_metric_value",
			Help: "A custom business metric value",
		},
		[]string{"type"},
	)
)

// Initialize sets up initial metric values
func Initialize() {
	ActiveConnections.Set(0)
	BusinessMetric.WithLabelValues("demo").Set(42.0)
}

// IncrementRequestCounter increments the request counter
func IncrementRequestCounter() {
	RequestCounter.Inc()
}

// IncrementRequestCounterVec increments the request counter with labels
func IncrementRequestCounterVec(method, status string) {
	RequestCounterVec.WithLabelValues(method, status).Inc()
}

// UpdateActiveConnections updates the active connections gauge
func UpdateActiveConnections(count float64) {
	ActiveConnections.Set(count)
}

// UpdateRequestDuration records the request duration
func UpdateRequestDuration(duration time.Duration) {
	RequestDuration.Observe(duration.Seconds())
}

// UpdateResponseSize records the response size
func UpdateResponseSize(size float64) {
	ResponseSize.Observe(size)
}

// UpdateBusinessMetric updates a business metric
func UpdateBusinessMetric(metricType string, value float64) {
	BusinessMetric.WithLabelValues(metricType).Set(value)
}

