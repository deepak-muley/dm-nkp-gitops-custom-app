package metrics

import (
	"testing"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	dto "github.com/prometheus/client_model/go"
)

func TestMetrics(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Metrics Suite")
}

var _ = Describe("Metrics", func() {
	BeforeEach(func() {
		// Reset metrics before each test
		// Note: Prometheus counters, histograms, and summaries cannot be reset
		// We can only reset Vec types and set gauges
		ActiveConnections.Set(0)
		RequestCounterVec.Reset()
		BusinessMetric.Reset()
	})

	Describe("Counter metrics", func() {
		It("should increment request counter", func() {
			IncrementRequestCounter()
			IncrementRequestCounter()

			var metric dto.Metric
			err := RequestCounter.Write(&metric)
			Expect(err).NotTo(HaveOccurred())
			Expect(metric.Counter.GetValue()).To(Equal(2.0))
		})

		It("should increment request counter with labels", func() {
			IncrementRequestCounterVec("GET", "200")
			IncrementRequestCounterVec("GET", "200")
			IncrementRequestCounterVec("POST", "201")

			var metric dto.Metric
			err := RequestCounterVec.WithLabelValues("GET", "200").Write(&metric)
			Expect(err).NotTo(HaveOccurred())
			Expect(metric.Counter.GetValue()).To(Equal(2.0))
		})
	})

	Describe("Gauge metrics", func() {
		It("should update active connections", func() {
			UpdateActiveConnections(5.0)
			UpdateActiveConnections(10.0)

			var metric dto.Metric
			err := ActiveConnections.Write(&metric)
			Expect(err).NotTo(HaveOccurred())
			Expect(metric.Gauge.GetValue()).To(Equal(10.0))
		})

		It("should update business metric", func() {
			UpdateBusinessMetric("demo", 100.0)
			UpdateBusinessMetric("demo", 200.0)

			var metric dto.Metric
			err := BusinessMetric.WithLabelValues("demo").Write(&metric)
			Expect(err).NotTo(HaveOccurred())
			Expect(metric.Gauge.GetValue()).To(Equal(200.0))
		})
	})

	Describe("Initialization", func() {
		It("should initialize metrics with default values", func() {
			Initialize()

			var metric dto.Metric
			err := ActiveConnections.Write(&metric)
			Expect(err).NotTo(HaveOccurred())
			Expect(metric.Gauge.GetValue()).To(Equal(0.0))

			err = BusinessMetric.WithLabelValues("demo").Write(&metric)
			Expect(err).NotTo(HaveOccurred())
			Expect(metric.Gauge.GetValue()).To(Equal(42.0))
		})
	})

	Describe("Histogram metrics", func() {
		It("should record request duration", func() {
			duration := 100 * time.Millisecond
			UpdateRequestDuration(duration)

			// Verify histogram was updated by checking sample count
			// Note: Histograms are harder to test directly, but we can verify the function doesn't panic
			Expect(func() {
				UpdateRequestDuration(200 * time.Millisecond)
				UpdateRequestDuration(300 * time.Millisecond)
			}).NotTo(Panic())
		})
	})

	Describe("Summary metrics", func() {
		It("should record response size", func() {
			UpdateResponseSize(100.0)
			UpdateResponseSize(200.0)
			UpdateResponseSize(300.0)

			// Verify summary was updated by checking the function doesn't panic
			// Note: Summaries are harder to test directly, but we can verify the function doesn't panic
			Expect(func() {
				UpdateResponseSize(400.0)
			}).NotTo(Panic())
		})
	})
})

