package metrics

import (
	"context"
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/metric"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.32.0"
)

var (
	// MeterProvider holds the global meter provider
	meterProvider *sdkmetric.MeterProvider
	// Meter for creating instruments
	meter metric.Meter
	// Mutex for thread safety
	mu sync.RWMutex

	// Counter: Total number of HTTP requests
	RequestCounter metric.Int64Counter

	// Gauge: Current number of active connections
	ActiveConnections      metric.Float64ObservableGauge
	activeConnectionsValue *float64Value

	// Histogram: Request duration in seconds
	RequestDuration metric.Float64Histogram

	// Histogram: Response size in bytes (replacing Summary)
	ResponseSize metric.Int64Histogram

	// CounterVec: Requests by method and status
	RequestCounterVec metric.Int64Counter

	// GaugeVec: Custom business metric values
	businessMetricValues map[string]*float64Value
)

// float64Value is a thread-safe wrapper for float64 values used in ObservableGauges
type float64Value struct {
	mu    sync.RWMutex
	value float64
}

func (f *float64Value) get() float64 {
	f.mu.RLock()
	defer f.mu.RUnlock()
	return f.value
}

func (f *float64Value) set(v float64) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.value = v
}

// Initialize sets up OpenTelemetry metrics
func Initialize() error {
	ctx := context.Background()

	// Get OTLP endpoint from environment, default to collector
	otlpEndpoint := getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")
	serviceName := getEnv("OTEL_SERVICE_NAME", "dm-nkp-gitops-custom-app")

	// Create resource with service name
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
			semconv.ServiceVersion("0.1.0"),
		),
	)
	if err != nil {
		return fmt.Errorf("failed to create resource: %w", err)
	}

	// Create OTLP metric exporter
	metricExporter, err := otlpmetricgrpc.New(ctx,
		otlpmetricgrpc.WithEndpoint(otlpEndpoint),
		otlpmetricgrpc.WithInsecure(), // For simplicity, use insecure in local/dev
	)
	if err != nil {
		return fmt.Errorf("failed to create metric exporter: %w", err)
	}

	// Create meter provider with periodic reader
	reader := sdkmetric.NewPeriodicReader(metricExporter,
		sdkmetric.WithInterval(30*time.Second),
	)

	meterProvider = sdkmetric.NewMeterProvider(
		sdkmetric.WithResource(res),
		sdkmetric.WithReader(reader),
	)

	otel.SetMeterProvider(meterProvider)

	// Create meter
	meter = otel.Meter("dm-nkp-gitops-custom-app/metrics")

	// Initialize maps
	businessMetricValues = make(map[string]*float64Value)
	activeConnectionsValue = &float64Value{value: 0.0}

	// Create RequestCounter
	RequestCounter, err = meter.Int64Counter(
		"http_requests_total",
		metric.WithDescription("Total number of HTTP requests"),
	)
	if err != nil {
		return fmt.Errorf("failed to create RequestCounter: %w", err)
	}

	// Create RequestCounterVec (counter with labels)
	RequestCounterVec, err = meter.Int64Counter(
		"http_requests_by_method_total",
		metric.WithDescription("Total number of HTTP requests by method"),
	)
	if err != nil {
		return fmt.Errorf("failed to create RequestCounterVec: %w", err)
	}

	// Create RequestDuration histogram
	RequestDuration, err = meter.Float64Histogram(
		"http_request_duration_seconds",
		metric.WithDescription("HTTP request duration in seconds"),
	)
	if err != nil {
		return fmt.Errorf("failed to create RequestDuration: %w", err)
	}

	// Create ResponseSize histogram (replacing Summary)
	ResponseSize, err = meter.Int64Histogram(
		"http_response_size_bytes",
		metric.WithDescription("HTTP response size in bytes"),
	)
	if err != nil {
		return fmt.Errorf("failed to create ResponseSize: %w", err)
	}

	// Create ActiveConnections observable gauge
	_, err = meter.Float64ObservableGauge(
		"http_active_connections",
		metric.WithDescription("Current number of active HTTP connections"),
		metric.WithFloat64Callback(func(ctx context.Context, o metric.Float64Observer) error {
			o.Observe(activeConnectionsValue.get())
			return nil
		}),
	)
	if err != nil {
		return fmt.Errorf("failed to create ActiveConnections: %w", err)
	}

	// Register observable callback for business metrics
	_, err = meter.Float64ObservableGauge(
		"business_metric_value",
		metric.WithDescription("A custom business metric value"),
		metric.WithFloat64Callback(func(ctx context.Context, o metric.Float64Observer) error {
			mu.RLock()
			defer mu.RUnlock()
			for metricType, val := range businessMetricValues {
				o.Observe(val.get(), metric.WithAttributes(attribute.String("type", metricType)))
			}
			return nil
		}),
	)
	if err != nil {
		return fmt.Errorf("failed to create BusinessMetric: %w", err)
	}

	// Initialize with default values
	UpdateActiveConnections(0)
	UpdateBusinessMetric("demo", 42.0)

	log.Printf("OpenTelemetry metrics initialized with endpoint: %s", otlpEndpoint)
	return nil
}

// Shutdown gracefully shuts down the meter provider
func Shutdown(ctx context.Context) error {
	if meterProvider != nil {
		return meterProvider.Shutdown(ctx)
	}
	return nil
}

// IncrementRequestCounter increments the request counter
func IncrementRequestCounter() {
	if RequestCounter != nil {
		RequestCounter.Add(context.Background(), 1)
	}
}

// IncrementRequestCounterVec increments the request counter with labels
func IncrementRequestCounterVec(method, status string) {
	if RequestCounterVec != nil {
		attrs := []attribute.KeyValue{
			attribute.String("method", method),
			attribute.String("status", status),
		}
		RequestCounterVec.Add(context.Background(), 1, metric.WithAttributes(attrs...))
	}
}

// UpdateActiveConnections updates the active connections gauge
func UpdateActiveConnections(count float64) {
	if activeConnectionsValue != nil {
		activeConnectionsValue.set(count)
	}
}

// UpdateRequestDuration records the request duration
func UpdateRequestDuration(duration time.Duration) {
	if RequestDuration != nil {
		RequestDuration.Record(context.Background(), duration.Seconds())
	}
}

// UpdateResponseSize records the response size
func UpdateResponseSize(size float64) {
	if ResponseSize != nil {
		ResponseSize.Record(context.Background(), int64(size))
	}
}

// UpdateBusinessMetric updates a business metric
func UpdateBusinessMetric(metricType string, value float64) {
	mu.Lock()
	defer mu.Unlock()

	// Initialize map if it's nil (happens when called before Initialize())
	if businessMetricValues == nil {
		businessMetricValues = make(map[string]*float64Value)
	}

	if _, exists := businessMetricValues[metricType]; !exists {
		businessMetricValues[metricType] = &float64Value{value: value}
	} else {
		businessMetricValues[metricType].set(value)
	}
}

// getEnv gets environment variable or returns default
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
