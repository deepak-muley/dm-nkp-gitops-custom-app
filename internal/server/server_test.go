package server

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// mockShutdowner is a mock implementation of shutdowner for testing
type mockShutdowner struct {
	err error
}

func (m *mockShutdowner) Shutdown(ctx context.Context) error {
	return m.err
}

func TestServer(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Server Suite")
}

var _ = Describe("Server", func() {
	var srv *Server

	BeforeEach(func() {
		srv = New("8080", "9090")
	})

	AfterEach(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
		defer cancel()
		_ = srv.Shutdown(ctx)
	})

	Describe("Server creation", func() {
		It("should create a new server with specified ports", func() {
			testSrv := New("8081", "9091")
			Expect(testSrv).NotTo(BeNil())
			Expect(testSrv.httpServer).NotTo(BeNil())
			Expect(testSrv.metricsServer).NotTo(BeNil())
			Expect(testSrv.httpServer.Addr).To(Equal(":8081"))
			Expect(testSrv.metricsServer.Addr).To(Equal(":9091"))

			// Clean up
			ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
			defer cancel()
			_ = testSrv.Shutdown(ctx)
		})
	})

	Describe("HTTP endpoints", func() {
		It("should handle root endpoint", func() {
			req := httptest.NewRequest("GET", "/", nil)
			w := httptest.NewRecorder()

			handleRoot(w, req)

			Expect(w.Code).To(Equal(http.StatusOK))
			Expect(w.Body.String()).To(ContainSubstring("Hello from dm-nkp-gitops-custom-app"))
		})

		It("should handle health endpoint", func() {
			req := httptest.NewRequest("GET", "/health", nil)
			w := httptest.NewRecorder()

			handleHealth(w, req)

			Expect(w.Code).To(Equal(http.StatusOK))
			Expect(w.Body.String()).To(ContainSubstring("healthy"))
		})

		It("should handle ready endpoint", func() {
			req := httptest.NewRequest("GET", "/ready", nil)
			w := httptest.NewRecorder()

			handleReady(w, req)

			Expect(w.Code).To(Equal(http.StatusOK))
			Expect(w.Body.String()).To(ContainSubstring("ready"))
		})
	})

	Describe("Start", func() {
		It("should start server and metrics server", func() {
			testSrv := New("8083", "9093")
			started := make(chan bool, 1)
			errChan := make(chan error, 1)

			// Start server in goroutine
			go func() {
				started <- true
				if err := testSrv.Start(); err != nil && err != http.ErrServerClosed {
					errChan <- err
				}
			}()

			// Wait a bit for server to start
			<-started
			time.Sleep(100 * time.Millisecond)

			// Verify server is running by checking if we can connect (or at least that it started)
			// Then shutdown
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			shutdownErr := testSrv.Shutdown(ctx)
			Expect(shutdownErr).To(BeNil())

			// Give a moment for goroutine to finish
			select {
			case err := <-errChan:
				Expect(err).To(BeNil())
			case <-time.After(500 * time.Millisecond):
				// No error, which is good
			}
		})

		It("should handle metrics server error in goroutine", func() {
			// Create a server that will have a conflict to trigger error path
			testSrv := New("8084", "9094")

			// Start it first to reserve the port
			go func() {
				_ = testSrv.Start()
			}()
			time.Sleep(50 * time.Millisecond)

			// Create another server trying to use same metrics port
			conflictingSrv := &Server{
				httpServer:    &http.Server{Addr: ":8085"},
				metricsServer: &http.Server{Addr: ":9094"}, // Same as testSrv
			}

			// This will trigger the error path in the goroutine
			go func() {
				_ = conflictingSrv.Start()
			}()
			time.Sleep(100 * time.Millisecond)

			// Clean up
			ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
			defer cancel()
			_ = testSrv.Shutdown(ctx)
			_ = conflictingSrv.Shutdown(ctx)
		})
	})

	Describe("Shutdown", func() {
		It("should shutdown server gracefully", func() {
			testSrv := New("8082", "9092")
			ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
			defer cancel()

			err := testSrv.Shutdown(ctx)
			Expect(err).To(BeNil())
		})

		It("should handle shutdown when server is nil", func() {
			testSrv := &Server{}
			ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
			defer cancel()

			err := testSrv.Shutdown(ctx)
			Expect(err).To(BeNil())
		})

		It("should handle shutdown when only httpServer is nil", func() {
			testSrv := &Server{
				metricsServer: &http.Server{Addr: ":9094"},
			}
			ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
			defer cancel()

			err := testSrv.Shutdown(ctx)
			Expect(err).To(BeNil())
		})

		It("should handle shutdown when only metricsServer is nil", func() {
			testSrv := &Server{
				httpServer: &http.Server{Addr: ":8084"},
			}
			ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
			defer cancel()

			err := testSrv.Shutdown(ctx)
			Expect(err).To(BeNil())
		})

		It("should handle shutdown error when httpServer fails after metricsServer error", func() {
			// Use mocks to test the error path where both shutdowns fail
			// This tests the branch where err != nil when httpServer.Shutdown is called

			// Create mock shutdowners that return errors
			mockMetricsShutdowner := &mockShutdowner{err: fmt.Errorf("metrics shutdown error")}
			mockHttpShutdowner := &mockShutdowner{err: fmt.Errorf("http shutdown error")}

			testSrv := &Server{
				metricsShutdowner: mockMetricsShutdowner,
				httpShutdowner:    mockHttpShutdowner,
			}

			ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
			defer cancel()

			// This should return the first error (metrics server error)
			// and exercise the path where err != nil when httpServer.Shutdown is called
			err := testSrv.Shutdown(ctx)
			Expect(err).NotTo(BeNil())
			Expect(err.Error()).To(ContainSubstring("metrics shutdown error"))
		})

		It("should handle shutdown error when only httpServer fails", func() {
			// Test the path where metricsServer succeeds but httpServer fails
			// This tests the branch where err == nil when httpServer.Shutdown is called

			mockMetricsShutdowner := &mockShutdowner{err: nil} // Success
			mockHttpShutdowner := &mockShutdowner{err: fmt.Errorf("http shutdown error")}

			testSrv := &Server{
				metricsShutdowner: mockMetricsShutdowner,
				httpShutdowner:    mockHttpShutdowner,
			}

			ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
			defer cancel()

			// This should return the http server error
			err := testSrv.Shutdown(ctx)
			Expect(err).NotTo(BeNil())
			Expect(err.Error()).To(ContainSubstring("http shutdown error"))
		})
	})
})
