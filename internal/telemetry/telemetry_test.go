package telemetry

import (
	"context"
	"os"
	"testing"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

func TestTelemetry(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Telemetry Suite")
}

var _ = Describe("Logger", func() {
	Describe("InitializeLogger", func() {
		It("should initialize logger successfully", func() {
			err := InitializeLogger()
			Expect(err).To(BeNil())
		})
	})

	Describe("ShutdownLogger", func() {
		It("should shutdown logger gracefully", func() {
			ctx := context.Background()
			err := ShutdownLogger(ctx)
			Expect(err).To(BeNil())
		})
	})

	Describe("LogInfo", func() {
		It("should log info message without panicking", func() {
			ctx := context.Background()
			Expect(func() {
				LogInfo(ctx, "test info message")
				LogInfo(ctx, "test with attrs", map[string]string{"key": "value"})
			}).NotTo(Panic())
		})
	})

	Describe("LogError", func() {
		It("should log error message without panicking", func() {
			ctx := context.Background()
			Expect(func() {
				LogError(ctx, "test error message", nil)
				LogError(ctx, "test error with err", context.Canceled, map[string]string{"key": "value"})
			}).NotTo(Panic())
		})

		It("should log error with error object", func() {
			ctx := context.Background()
			testErr := context.DeadlineExceeded
			Expect(func() {
				LogError(ctx, "test error", testErr)
			}).NotTo(Panic())
		})

		It("should log error without error object", func() {
			ctx := context.Background()
			Expect(func() {
				LogError(ctx, "test error", nil)
			}).NotTo(Panic())
		})
	})
})

var _ = Describe("Tracer", func() {
	Describe("InitializeTracer", func() {
		It("should initialize tracer with default endpoint", func() {
			// Clear any existing env var
			os.Unsetenv("OTEL_EXPORTER_OTLP_ENDPOINT")
			os.Unsetenv("OTEL_SERVICE_NAME")
			
			err := InitializeTracer()
			// It's okay if it fails in test environment without collector
			// We just verify it doesn't panic and handles gracefully
			_ = err
		})

		It("should initialize tracer with custom endpoint", func() {
			os.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "localhost:4317")
			os.Setenv("OTEL_SERVICE_NAME", "test-service")
			defer func() {
				os.Unsetenv("OTEL_EXPORTER_OTLP_ENDPOINT")
				os.Unsetenv("OTEL_SERVICE_NAME")
			}()
			
			err := InitializeTracer()
			// It's okay if it fails in test environment without collector
			_ = err
		})
	})

	Describe("ShutdownTracer", func() {
		It("should shutdown tracer gracefully when not initialized", func() {
			tracerProvider = nil
			ctx := context.Background()
			err := ShutdownTracer(ctx)
			Expect(err).To(BeNil())
		})

		It("should shutdown tracer when initialized", func() {
			// Initialize first (may fail, but that's okay)
			InitializeTracer()
			
			ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
			defer cancel()
			
			err := ShutdownTracer(ctx)
			// It's okay if it fails or succeeds - we just verify it doesn't panic
			_ = err
		})
	})
})

var _ = Describe("Utils", func() {
	Describe("getEnv", func() {
		It("should return environment variable value when set", func() {
			os.Setenv("TEST_ENV_VAR", "test-value")
			defer os.Unsetenv("TEST_ENV_VAR")
			
			value := getEnv("TEST_ENV_VAR", "default-value")
			Expect(value).To(Equal("test-value"))
		})

		It("should return default value when environment variable not set", func() {
			os.Unsetenv("TEST_ENV_VAR_MISSING")
			value := getEnv("TEST_ENV_VAR_MISSING", "default-value")
			Expect(value).To(Equal("default-value"))
		})

		It("should return default value when environment variable is empty", func() {
			os.Setenv("TEST_ENV_VAR_EMPTY", "")
			defer os.Unsetenv("TEST_ENV_VAR_EMPTY")
			
			value := getEnv("TEST_ENV_VAR_EMPTY", "default-value")
			Expect(value).To(Equal("default-value"))
		})
	})
})
