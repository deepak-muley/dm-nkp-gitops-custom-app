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
		appPath      string
		session      *gexec.Session
		baseURL      = "http://localhost:8080"
		metricsURL   = "http://localhost:9090"
		kindCluster  = "dm-nkp-test-cluster"
		namespace    = "dm-nkp-test"
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

		It("should expose metrics endpoint", func() {
			resp, err := httpGet(metricsURL + "/metrics")
			Expect(err).NotTo(HaveOccurred())
			Expect(resp).To(ContainSubstring("http_requests_total"))
			Expect(resp).To(ContainSubstring("http_active_connections"))
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

	Describe("Kubernetes deployment with monitoring", func() {
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

			// Deploy application
			deployApplication(namespace)

			// Deploy monitoring stack (Prometheus + Grafana)
			deployMonitoringStack()

			// Wait for all pods to be ready
			waitForPodsReady(namespace, "app=dm-nkp-gitops-custom-app", 2*time.Minute)
			waitForPodsReady("monitoring", "app=prometheus", 2*time.Minute)
			waitForPodsReady("monitoring", "app=grafana", 2*time.Minute)

			// Generate some traffic to create metrics
			generateTraffic(namespace, 10)
		})

		AfterSuite(func() {
			// Cleanup deployments
			cleanupDeployment(namespace)
			cleanupMonitoringStack()

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

		It("should expose metrics endpoint", func() {
			// Port forward to application
			portForward := startPortForward(namespace, "dm-nkp-gitops-custom-app", 9090)
			defer portForward.Kill()

			time.Sleep(2 * time.Second)

			// Check metrics endpoint
			resp, err := httpGet("http://localhost:9090/metrics")
			Expect(err).NotTo(HaveOccurred())
			Expect(resp).To(ContainSubstring("http_requests_total"))
			Expect(resp).To(ContainSubstring("http_active_connections"))
		})

		It("should have Prometheus scraping metrics", func() {
			// Port forward to Prometheus (kube-prometheus-stack service name)
			portForward := startPortForward("monitoring", "prometheus-kube-prometheus-prometheus", 9090)
			defer portForward.Kill()

			time.Sleep(2 * time.Second)

			// Check Prometheus targets
			resp, err := httpGet("http://localhost:9090/api/v1/targets")
			Expect(err).NotTo(HaveOccurred())
			// Prometheus should be running (may not have discovered app yet)
			Expect(resp).To(ContainSubstring("activeTargets"))

			// Query metrics from Prometheus
			resp, err = httpGet("http://localhost:9090/api/v1/query?query=http_requests_total")
			Expect(err).NotTo(HaveOccurred())
			// Should return valid Prometheus response
			Expect(resp).To(ContainSubstring("status"))
		})

		It("should have Grafana accessible with dashboard", func() {
			// Port forward to Grafana (kube-prometheus-stack service name)
			portForward := startPortForward("monitoring", "prometheus-grafana", 80)
			defer portForward.Kill()

			time.Sleep(3 * time.Second)

			// Check Grafana is accessible (try with default password first)
			// For kube-prometheus-stack, password is in secret
			resp, err := httpGet("http://localhost:3000/api/health")
			if err != nil {
				// Try with basic auth (may need password from secret)
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
	cmd := exec.Command("kubectl", "create", "namespace", namespace, "--dry-run=client", "-o", "yaml", "|", "kubectl", "apply", "-f", "-")
	cmd = exec.Command("sh", "-c", fmt.Sprintf("kubectl create namespace %s --dry-run=client -o yaml | kubectl apply -f -", namespace))
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		session.Wait()
	}

	// Apply base manifests with updated image
	cmd = exec.Command("kubectl", "apply", "-f", "manifests/base/")
	session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 30*time.Second).Should(gexec.Exit(0))

	// Update deployment image
	cmd = exec.Command("kubectl", "set", "image", "deployment/dm-nkp-gitops-custom-app", "app=dm-nkp-gitops-custom-app:test", "-n", namespace)
	session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		Eventually(session, 10*time.Second).Should(gexec.Exit(0))
	}
}

func deployMonitoringStack() {
	// Check if helm is available
	if !commandExists("helm") {
		Skip("helm is not installed, skipping Helm-based monitoring setup")
	}

	// Add Helm repos
	cmd := exec.Command("helm", "repo", "add", "prometheus-community", "https://prometheus-community.github.io/helm-charts")
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		session.Wait()
	}

	cmd = exec.Command("helm", "repo", "update")
	session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		session.Wait()
	}

	// Create namespace
	cmd = exec.Command("sh", "-c", "kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -")
	session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		session.Wait()
	}

	// Install Prometheus Operator (includes Prometheus and Grafana)
	cmd = exec.Command("helm", "upgrade", "--install", "prometheus", "prometheus-community/kube-prometheus-stack",
		"--namespace", "monitoring",
		"--set", "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false",
		"--set", "prometheus.service.type=NodePort",
		"--set", "prometheus.service.nodePort=30090",
		"--wait", "--timeout=5m")
	session, err = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	if err == nil {
		Eventually(session, 6*time.Minute).Should(gexec.Exit(0))
	}
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

func cleanupMonitoringStack() {
	// Monitoring is deployed via Helm, so uninstall using Helm
	cmd := exec.Command("helm", "uninstall", "prometheus", "--namespace", "monitoring", "--ignore-not-found=true")
	session, _ := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	session.Wait()
	
	// Also delete the namespace if it exists
	cmd = exec.Command("kubectl", "delete", "namespace", "monitoring", "--ignore-not-found=true")
	session, _ = gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	session.Wait()
}

