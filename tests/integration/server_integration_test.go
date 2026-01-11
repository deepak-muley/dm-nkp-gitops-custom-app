//go:build integration
// +build integration

package integration

import (
	"context"
	"fmt"
	"net/http"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	"github.com/deepak-muley/dm-nkp-gitops-custom-app/internal/server"
)

var _ = Describe("Server Integration", func() {
	var srv *server.Server
	var baseURL string

	BeforeEach(func() {
		baseURL = "http://localhost:8080"
		srv = server.New("8080")

		go func() {
			if err := srv.Start(); err != nil && err != http.ErrServerClosed {
				Fail(fmt.Sprintf("Failed to start server: %v", err))
			}
		}()

		// Wait for server to start
		Eventually(func() error {
			resp, err := http.Get(baseURL + "/health")
			if err != nil {
				return err
			}
			resp.Body.Close()
			return nil
		}, 5*time.Second, 500*time.Millisecond).ShouldNot(HaveOccurred())
	})

	AfterEach(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		srv.Shutdown(ctx)
	})

	Describe("Health endpoints", func() {
		It("should respond to health check", func() {
			resp, err := http.Get(baseURL + "/health")
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			resp.Body.Close()
		})

		It("should respond to readiness check", func() {
			resp, err := http.Get(baseURL + "/ready")
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			resp.Body.Close()
		})
	})

	Describe("Main endpoint", func() {
		It("should serve the root endpoint", func() {
			resp, err := http.Get(baseURL + "/")
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			resp.Body.Close()
		})
	})

	// Metrics endpoint tests removed - metrics are now exported via OpenTelemetry
	// rather than via a separate /metrics HTTP endpoint
	// Metrics are collected by the OTel Collector and forwarded to Prometheus
})
