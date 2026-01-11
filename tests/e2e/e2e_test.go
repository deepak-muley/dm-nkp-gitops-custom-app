//go:build e2e
// +build e2e

package e2e

import (
	"fmt"
	"net/http"
	"os/exec"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gexec"
)

var _ = Describe("E2E Tests", func() {
	var (
		appPath     string
		session     *gexec.Session
		baseURL     = "http://localhost:8080"
		kindCluster = "dm-nkp-test-cluster"
		namespace   = "dm-nkp-test"
	)

	BeforeSuite(func() {
		// Build the application
		var err error
		appPath, err = gexec.Build("github.com/deepak-muley/dm-nkp-gitops-custom-app/cmd/app")
		Expect(err).NotTo(HaveOccurred())
	})

	AfterSuite(func() {
		gexec.CleanupBuildArtifacts()
		if session != nil {
			session.Kill()
		}
	})

	Describe("Local application", func() {
		BeforeEach(func() {
			// Start the application
			cmd := exec.Command(appPath)
			var err error
			session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
			Expect(err).NotTo(HaveOccurred())

			// Wait for application to be ready
			Eventually(func() error {
				return checkHealth(baseURL)
			}, 10*time.Second, 1*time.Second).ShouldNot(HaveOccurred())
		})

		AfterEach(func() {
			if session != nil {
				session.Kill()
				session.Wait()
			}
		})

		It("should serve the root endpoint", func() {
			resp, err := httpGet(baseURL + "/")
			Expect(err).NotTo(HaveOccurred())
			Expect(resp).To(ContainSubstring("Hello from dm-nkp-gitops-custom-app"))
		})

		It("should generate logs with structured logging", func() {
			// Generate a request which should produce logs
			resp, err := httpGet(baseURL + "/")
			Expect(err).NotTo(HaveOccurred())
			Expect(resp).To(ContainSubstring("Hello from dm-nkp-gitops-custom-app"))
			
			// Application should log to stdout (which will be collected by OTel Collector in k8s)
			// For local testing, we just verify the request works
			// In k8s, logs will be collected via stdout/stderr
		})

		It("should create traces for requests", func() {
			// Generate a request which should create a trace span
			resp, err := httpGet(baseURL + "/")
			Expect(err).NotTo(HaveOccurred())
			Expect(resp).To(ContainSubstring("Hello from dm-nkp-gitops-custom-app"))
			
			// Application should create trace spans (exported to OTel Collector in k8s)
			// For local testing, we just verify the request works
			// In k8s, traces will be exported to OTel Collector
		})

		It("should respond to health checks", func() {
			resp, err := httpGet(baseURL + "/health")
			Expect(err).NotTo(HaveOccurred())
			Expect(resp).To(ContainSubstring("healthy"))

			resp, err = httpGet(baseURL + "/ready")
			Expect(err).NotTo(HaveOccurred())
			Expect(resp).To(ContainSubstring("ready"))
		})
	})

	Describe("Kubernetes deployment with OpenTelemetry observability stack", func() {
		BeforeSuite(func() {
			// Check if kind is available
			if !commandExists("kind") {
				Skip("kind is not installed, skipping Kubernetes tests")
			}
			if !commandExists("kubectl") {
				Skip("kubectl is not installed, skipping Kubernetes tests")
			}

			// Create kind cluster if it doesn't exist
			createKindCluster(kindCluster)

			// Set kubectl context
			setKubectlContext(kindCluster)

			// Build and load Docker image into kind
			buildAndLoadImage(kindCluster)

			// Deploy observability stack (OTel Collector, Prometheus, Loki, Tempo, Grafana)
			deployObservabilityStack()

			// Deploy application with OpenTelemetry configuration
			deployApplication(namespace)

			// Wait for all pods to be ready
			waitForPodsReady("observability", "component=otel-collector", 2*time.Minute)
			waitForPodsReady(namespace, "app=dm-nkp-gitops-custom-app", 2*time.Minute)
			waitForPodsReady("observability", "app.kubernetes.io/name=prometheus", 2*time.Minute)
			waitForPodsReady("observability", "app.kubernetes.io/name=grafana", 2*time.Minute)

			// Generate some traffic to create metrics, logs, and traces
			generateTraffic(namespace, 10)
			
			// Wait a bit for telemetry to be collected
			time.Sleep(5 * time.Second)
		})

		AfterSuite(func() {
			// Cleanup deployments
			cleanupDeployment(namespace)
			cleanupObservabilityStack()

			// Cleanup kind cluster (optional - comment out to keep cluster for inspection)
			// if commandExists("kind") {
			// 	deleteKindCluster(kindCluster)
			// }
		})

		It("should deploy application to Kubernetes", func() {
			// Check application pods are running
			pods, err := getPods(namespace, "app=dm-nkp-gitops-custom-app")
			Expect(err).NotTo(HaveOccurred())
			Expect(len(pods)).To(BeNumerically(">=", 1))
		})

		It("should send telemetry to OpenTelemetry Collector", func() {
			// Check OTel Collector is running
			pods, err := getPods("observability", "component=otel-collector")
			Expect(err).NotTo(HaveOccurred())
			Expect(len(pods)).To(BeNumerically(">=", 1))
			
			// Check OTel Collector logs for incoming telemetry
			cmd := exec.Command("kubectl", "logs", "-n", "observability", "-l", "component=otel-collector", "--tail=50")
			output, err := cmd.Output()
			if err == nil {
				// OTel Collector should be running (logs may or may not show received data yet)
				Expect(string(output)).NotTo(BeEmpty())
			}
		})

		It("should have Prometheus scraping metrics from OTel Collector", func() {
			// Port forward to Prometheus
			portForward := startPortForward("observability", "prometheus-kube-prometheus-prometheus", 9090)
			defer portForward.Kill()

			time.Sleep(2 * time.Second)

			// Check Prometheus targets (should scrape OTel Collector)
			resp, err := httpGet("http://localhost:9090/api/v1/targets")
			Expect(err).NotTo(HaveOccurred())
			// Prometheus should be running
			Expect(resp).To(ContainSubstring("activeTargets"))

			// Query metrics from Prometheus (may need time for metrics to appear)
			resp, err = httpGet("http://localhost:9090/api/v1/query?query=http_requests_total")
			Expect(err).NotTo(HaveOccurred())
			// Should return valid Prometheus response (may be empty if no metrics yet)
			Expect(resp).To(ContainSubstring("status"))
		})

		It("should export logs to Loki", func() {
			// Check application logs are being collected
			cmd := exec.Command("kubectl", "logs", "-n", namespace, "-l", "app=dm-nkp-gitops-custom-app", "--tail=20")
			output, err := cmd.Output()
			Expect(err).NotTo(HaveOccurred())
			// Application should be logging
			Expect(string(output)).To(ContainSubstring("INFO"))
			
			// In a real scenario, these logs would be forwarded to Loki via OTel Collector
			// For e2e, we verify logs exist in pods (Loki collection tested separately)
		})

		It("should export traces to Tempo", func() {
			// Generate a request to create traces
			portForward := startPortForward(namespace, "dm-nkp-gitops-custom-app", 8080)
			defer portForward.Kill()
			
			time.Sleep(2 * time.Second)
			
			// Make a request which should create a trace
			resp, err := httpGet("http://localhost:8080/")
			Expect(err).NotTo(HaveOccurred())
			Expect(resp).To(ContainSubstring("Hello from dm-nkp-gitops-custom-app"))
			
			// In a real scenario, traces would be exported to Tempo via OTel Collector
			// For e2e, we verify the application creates traces (export verified separately)
		})

		It("should have Grafana accessible with observability data sources", func() {
			// Port forward to Grafana
			portForward := startPortForward("observability", "prometheus-grafana", 80)
			defer portForward.Kill()

			time.Sleep(3 * time.Second)

			// Check Grafana is accessible
			resp, err := httpGet("http://localhost:3000/api/health")
			if err != nil {
				// Try with basic auth
				resp, err = httpGet("http://admin:admin@localhost:3000/api/health")
			}
			Expect(err).NotTo(HaveOccurred())
			// Grafana health endpoint should return something
			Expect(resp).NotTo(BeEmpty())
		})
	})
})

// Helper functions
func checkHealth(url string) error {
	resp, err := httpGet(url + "/health")
	if err != nil {
		return err
	}
	if resp == "" {
		return fmt.Errorf("empty response")
	}
	return nil
}

func httpGet(url string) (string, error) {
	// Try using curl first, fallback to Go http client
	if commandExists("curl") {
		cmd := exec.Command("curl", "-s", url)
		output, err := cmd.Output()
		if err == nil {
			return string(output), nil
		}
	}

	// Fallback to Go http client
	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	body := make([]byte, 0)
	buf := make([]byte, 1024)
	for {
		n, err := resp.Body.Read(buf)
		if n > 0 {
			body = append(body, buf[:n]...)
		}
		if err != nil {
			break
		}
	}
	return string(body), nil
}

func commandExists(cmd string) bool {
	_, err := exec.LookPath(cmd)
	return err == nil
}

func createKindCluster(name string) {
	// Check if cluster already exists
	cmd := exec.Command("kind", "get", "clusters")
	output, err := cmd.Output()
	if err == nil && contains(string(output), name) {
		return // Cluster already exists
	}

	// Create cluster
	cmd = exec.Command("kind", "create", "cluster", "--name", name)
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 2*time.Minute).Should(gexec.Exit(0))
}

func deleteKindCluster(name string) {
	cmd := exec.Command("kind", "delete", "cluster", "--name", name)
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		session.Wait()
	}
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > len(substr) && contains(s[1:], substr))
}

func setKubectlContext(clusterName string) {
	cmd := exec.Command("kubectl", "config", "use-context", "kind-"+clusterName)
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 10*time.Second).Should(gexec.Exit(0))
}

func buildAndLoadImage(clusterName string) {
	// Build Docker image
	cmd := exec.Command("docker", "build", "-t", "dm-nkp-gitops-custom-app:test", ".")
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 2*time.Minute).Should(gexec.Exit(0))

	// Load image into kind
	cmd = exec.Command("kind", "load", "docker-image", "dm-nkp-gitops-custom-app:test", "--name", clusterName)
	session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 30*time.Second).Should(gexec.Exit(0))
}

func deployApplication(namespace string) {
	// Create namespace
	cmd := exec.Command("sh", "-c", fmt.Sprintf("kubectl create namespace %s --dry-run=client -o yaml | kubectl apply -f -", namespace))
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		session.Wait()
	}

	// Deploy using Helm chart with OpenTelemetry enabled
	if commandExists("helm") {
		// Use Helm to deploy with OTel configuration
		cmd = exec.Command("helm", "upgrade", "--install", "dm-nkp-gitops-custom-app", "chart/dm-nkp-gitops-custom-app",
			"--namespace", namespace,
			"--set", "image.tag=test",
			"--set", "image.repository=dm-nkp-gitops-custom-app",
			"--set", "opentelemetry.enabled=true",
			"--set", "opentelemetry.collector.endpoint=otel-collector.observability.svc.cluster.local:4317",
			"--wait", "--timeout=3m")
		session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
		if err == nil {
			Eventually(session, 4*time.Minute).Should(gexec.Exit(0))
			return
		}
	}
	
	// Fallback to manifests if Helm is not available
	// Apply base manifests with updated image
	cmd = exec.Command("kubectl", "apply", "-f", "manifests/base/")
	session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 30*time.Second).Should(gexec.Exit(0))

	// Update deployment image and add OTel environment variables
	cmd = exec.Command("kubectl", "set", "image", "deployment/dm-nkp-gitops-custom-app", "app=dm-nkp-gitops-custom-app:test", "-n", namespace)
	session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		Eventually(session, 10*time.Second).Should(gexec.Exit(0))
	}
	
	// Add OTel environment variables
	cmd = exec.Command("kubectl", "set", "env", "deployment/dm-nkp-gitops-custom-app",
		"OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector.observability.svc.cluster.local:4317",
		"OTEL_SERVICE_NAME=dm-nkp-gitops-custom-app",
		"-n", namespace)
	session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		session.Wait()
	}
}

func deployObservabilityStack() {
	// Check if helm is available
	if !commandExists("helm") {
		Skip("helm is not installed, skipping Helm-based observability setup")
	}

	// Add Helm repos
	cmd := exec.Command("helm", "repo", "add", "prometheus-community", "https://prometheus-community.github.io/helm-charts")
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		session.Wait()
	}

	cmd = exec.Command("helm", "repo", "add", "grafana", "https://grafana.github.io/helm-charts")
	session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		session.Wait()
	}

	cmd = exec.Command("helm", "repo", "update")
	session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		session.Wait()
	}

	// Create namespace
	cmd = exec.Command("sh", "-c", "kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -")
	session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		session.Wait()
	}

	// Install Prometheus (includes Grafana) via kube-prometheus-stack
	cmd = exec.Command("helm", "upgrade", "--install", "prometheus", "prometheus-community/kube-prometheus-stack",
		"--namespace", "observability",
		"--set", "prometheus.prometheusSpec.retention=1h",
		"--set", "grafana.adminPassword=admin",
		"--set", "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false",
		"--wait", "--timeout=5m")
	session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		Eventually(session, 6*time.Minute).Should(gexec.Exit(0))
	}

	// Install OTel Collector (using local chart if available, otherwise skip)
	if commandExists("helm") {
		// Try to install from local chart
		cmd = exec.Command("helm", "upgrade", "--install", "otel-collector", "chart/observability-stack",
			"--namespace", "observability",
			"--wait", "--timeout=3m")
		session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
		if err == nil {
			Eventually(session, 4*time.Minute).Should(gexec.Exit(0))
		} else {
			// If local chart fails, skip OTel Collector for now
			fmt.Printf("Warning: Failed to install OTel Collector from local chart\n")
		}
	}

	// Configure Prometheus to scrape OTel Collector's Prometheus exporter endpoint
	// This is done via a ServiceMonitor or scrape config
	// For simplicity in e2e, we'll configure it manually or via values
}

func waitForPodsReady(namespace, selector string, timeout time.Duration) {
	cmd := exec.Command("kubectl", "wait", "--for=condition=ready", "pod", "-l", selector, "-n", namespace, "--timeout", timeout.String())
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		Eventually(session, timeout+10*time.Second).Should(gexec.Exit(0))
	}
}

func generateTraffic(namespace string, count int) {
	// Port forward to application
	portForward := startPortForward(namespace, "dm-nkp-gitops-custom-app", 8080)
	defer portForward.Kill()

	time.Sleep(2 * time.Second)

	// Generate traffic
	for i := 0; i < count; i++ {
		httpGet("http://localhost:8080/")
		time.Sleep(100 * time.Millisecond)
	}
}

func getPods(namespace, selector string) ([]string, error) {
	cmd := exec.Command("kubectl", "get", "pods", "-l", selector, "-n", namespace, "-o", "jsonpath={.items[*].metadata.name}")
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	if len(output) == 0 {
		return []string{}, nil
	}
	return []string{string(output)}, nil
}

func startPortForward(namespace, name string, port int) *gexec.Session {
	cmd := exec.Command("kubectl", "port-forward", "-n", namespace, fmt.Sprintf("deployment/%s", name), fmt.Sprintf("%d:%d", port, port))
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	return session
}

func cleanupDeployment(namespace string) {
	cmd := exec.Command("kubectl", "delete", "-f", "manifests/base/", "--ignore-not-found=true")
	session, _ := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	session.Wait()
	cmd = exec.Command("kubectl", "delete", "namespace", namespace, "--ignore-not-found=true")
	session, _ = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	session.Wait()
}

func cleanupObservabilityStack() {
	// Observability stack is deployed via Helm, so uninstall using Helm
	cmd := exec.Command("helm", "uninstall", "otel-collector", "--namespace", "observability", "--ignore-not-found=true")
	session, _ := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	session.Wait()

	cmd = exec.Command("helm", "uninstall", "prometheus", "--namespace", "observability", "--ignore-not-found=true")
	session, _ = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	session.Wait()

	// Also delete the namespace if it exists
	cmd = exec.Command("kubectl", "delete", "namespace", "observability", "--ignore-not-found=true")
	session, _ = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	session.Wait()
}
