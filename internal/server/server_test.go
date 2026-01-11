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
		srv = New("8080")
	})

	AfterEach(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
		defer cancel()
		_ = srv.Shutdown(ctx)
	})

	Describe("Server creation", func() {
		It("should create a new server with specified port", func() {
			testSrv := New("8081")
			Expect(testSrv).NotTo(BeNil())
			Expect(testSrv.httpServer).NotTo(BeNil())
			Expect(testSrv.httpServer.Addr).To(Equal(":8081"))

			// Clean up
			ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
			defer cancel()
			_ = testSrv.Shutdown(ctx)
		})

		It("should create a server with different ports", func() {
			testSrv1 := New("9000")
			Expect(testSrv1.httpServer.Addr).To(Equal(":9000"))
			
			testSrv2 := New("9001")
			Expect(testSrv2.httpServer.Addr).To(Equal(":9001"))

			// Clean up
			ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
			defer cancel()
			_ = testSrv1.Shutdown(ctx)
			_ = testSrv2.Shutdown(ctx)
		})

		It("should create server with handler configured", func() {
			testSrv := New("8084")
			Expect(testSrv.httpServer.Handler).NotTo(BeNil())

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

		It("should handle root endpoint with different methods", func() {
			req := httptest.NewRequest("POST", "/", nil)
			w := httptest.NewRecorder()

			handleRoot(w, req)

			Expect(w.Code).To(Equal(http.StatusOK))
			Expect(w.Body.String()).To(ContainSubstring("Hello from dm-nkp-gitops-custom-app"))
		})

		It("should handle root endpoint with context", func() {
			req := httptest.NewRequest("GET", "/", nil)
			req = req.WithContext(context.Background())
			w := httptest.NewRecorder()

			handleRoot(w, req)

			Expect(w.Code).To(Equal(http.StatusOK))
		})

		It("should handle health endpoint", func() {
			req := httptest.NewRequest("GET", "/health", nil)
			w := httptest.NewRecorder()

			handleHealth(w, req)

			Expect(w.Code).To(Equal(http.StatusOK))
			Expect(w.Body.String()).To(ContainSubstring("healthy"))
		})

		It("should handle health endpoint with context", func() {
			req := httptest.NewRequest("GET", "/health", nil)
			req = req.WithContext(context.Background())
			w := httptest.NewRecorder()

			handleHealth(w, req)

			Expect(w.Code).To(Equal(http.StatusOK))
		})

		It("should handle ready endpoint", func() {
			req := httptest.NewRequest("GET", "/ready", nil)
			w := httptest.NewRecorder()

			handleReady(w, req)

			Expect(w.Code).To(Equal(http.StatusOK))
			Expect(w.Body.String()).To(ContainSubstring("ready"))
		})

		It("should handle ready endpoint with context", func() {
			req := httptest.NewRequest("GET", "/ready", nil)
			req = req.WithContext(context.Background())
			w := httptest.NewRecorder()

			handleReady(w, req)

			Expect(w.Code).To(Equal(http.StatusOK))
		})
	})

	Describe("Start", func() {
		It("should start server", func() {
			testSrv := New("8083")
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
	})

	Describe("Shutdown", func() {
		It("should shutdown server gracefully", func() {
			testSrv := New("8082")
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

		It("should handle shutdown error when httpServer fails", func() {
			mockHttpShutdowner := &mockShutdowner{err: fmt.Errorf("http shutdown error")}

			testSrv := &Server{
				httpShutdowner: mockHttpShutdowner,
			}

			ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
			defer cancel()

			err := testSrv.Shutdown(ctx)
			Expect(err).NotTo(BeNil())
			Expect(err.Error()).To(ContainSubstring("http shutdown error"))
		})
	})
})
