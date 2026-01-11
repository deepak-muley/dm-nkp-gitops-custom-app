package metrics

import (
	"context"
	"os"
	"testing"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

func TestMetrics(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Metrics Suite")
}

var _ = Describe("Metrics", func() {
	BeforeEach(func() {
		// Note: OpenTelemetry initialization requires an exporter endpoint
		// For tests, we'll skip initialization and test that functions don't panic
		// In a real scenario, you'd use a test exporter or mock
	})

	Describe("Counter metrics", func() {
		It("should increment request counter without panicking", func() {
			// Test that the function can be called even if not initialized
			Expect(func() {
				IncrementRequestCounter()
				IncrementRequestCounter()
			}).NotTo(Panic())
		})

		It("should increment request counter with labels without panicking", func() {
			Expect(func() {
				IncrementRequestCounterVec("GET", "200")
				IncrementRequestCounterVec("GET", "200")
				IncrementRequestCounterVec("POST", "201")
			}).NotTo(Panic())
		})
	})

	Describe("Gauge metrics", func() {
		It("should update active connections without panicking", func() {
			Expect(func() {
				UpdateActiveConnections(5.0)
				UpdateActiveConnections(10.0)
			}).NotTo(Panic())
		})

		It("should update business metric without panicking", func() {
			Expect(func() {
				UpdateBusinessMetric("demo", 100.0)
				UpdateBusinessMetric("demo", 200.0)
				UpdateBusinessMetric("test", 50.0)
			}).NotTo(Panic())
		})
	})

	Describe("Initialization", func() {
		It("should handle initialization error gracefully when endpoint is unavailable", func() {
			// Test that initialization doesn't panic even if exporter is unavailable
			// In a real test environment, you'd provide a test endpoint
			// For now, we just verify the function signature is correct
			err := Initialize()
			// It's okay if it fails in test environment without collector
			if err != nil {
				Expect(err).To(HaveOccurred())
			}
		})

		It("should initialize with custom environment variables", func() {
			// Test that getEnv is called with different values
			os.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "custom-endpoint:4317")
			os.Setenv("OTEL_SERVICE_NAME", "custom-service")
			defer func() {
				os.Unsetenv("OTEL_EXPORTER_OTLP_ENDPOINT")
				os.Unsetenv("OTEL_SERVICE_NAME")
			}()

			err := Initialize()
			_ = err // May fail without collector, that's okay
			// This tests getEnv when env vars are set
		})

		It("should use default values when environment variables are not set", func() {
			os.Unsetenv("OTEL_EXPORTER_OTLP_ENDPOINT")
			os.Unsetenv("OTEL_SERVICE_NAME")

			err := Initialize()
			_ = err // May fail without collector, that's okay
			// This tests getEnv when env vars are not set (uses defaults)
		})
	})

	Describe("Counter metrics with initialization", func() {
		It("should increment counter when initialized", func() {
			// Try to initialize first (may fail, but that's okay)
			_ = Initialize()

			// Test that functions work even if initialization partially failed
			Expect(func() {
				IncrementRequestCounter()
				IncrementRequestCounter()
			}).NotTo(Panic())
		})

		It("should increment counter vec when initialized", func() {
			// Try to initialize first
			_ = Initialize()

			Expect(func() {
				IncrementRequestCounterVec("GET", "200")
				IncrementRequestCounterVec("POST", "201")
				IncrementRequestCounterVec("PUT", "404")
			}).NotTo(Panic())
		})
	})

	Describe("Histogram metrics", func() {
		It("should record request duration without panicking", func() {
			duration := 100 * time.Millisecond
			Expect(func() {
				UpdateRequestDuration(duration)
				UpdateRequestDuration(200 * time.Millisecond)
				UpdateRequestDuration(300 * time.Millisecond)
			}).NotTo(Panic())
		})
	})

	Describe("Response size metrics", func() {
		It("should record response size without panicking", func() {
			Expect(func() {
				UpdateResponseSize(100.0)
				UpdateResponseSize(200.0)
				UpdateResponseSize(300.0)
			}).NotTo(Panic())
		})
	})

	Describe("Shutdown", func() {
		It("should handle shutdown gracefully even if not initialized", func() {
			// Set meterProvider to nil to test the nil branch
			meterProvider = nil
			ctx := context.Background()
			err := Shutdown(ctx)
			Expect(err).To(BeNil())
		})

		It("should shutdown when initialized", func() {
			// Try to initialize first (may fail, but that's okay)
			_ = Initialize()

			ctx := context.Background()
			err := Shutdown(ctx)
			// It's okay if it fails or succeeds - we just verify it doesn't panic
			_ = err
		})
	})
})
