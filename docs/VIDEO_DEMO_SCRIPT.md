# Video Demo Script - OpenTelemetry Observability Stack with Grafana Dashboards

## Video Overview

**Title**: "Complete OpenTelemetry Observability Stack with Grafana Dashboards - Full Demo"

**Duration**: ~15-20 minutes

**Target Audience**: DevOps Engineers, SREs, Developers working with Kubernetes and observability

**Video Structure**:
1. Introduction & Overview (2 min)
2. Architecture Explanation (3 min)
3. Prerequisites Setup (2 min)
4. Local Testing Demo (5 min)
5. Production Deployment Demo (3 min)
6. Dashboard Walkthrough (3 min)
7. Troubleshooting & Tips (1 min)
8. Conclusion & Resources (1 min)

---

## Detailed Script

### Segment 1: Introduction & Overview (2 minutes)

**[Screen: Show repository README, then switch to terminal]**

**Narration:**
"Hey everyone! Welcome to this complete demo of an OpenTelemetry-based observability stack with Grafana dashboards for metrics, logs, and traces.

In this video, I'll show you how to:
- Set up a complete observability stack using OpenTelemetry
- Deploy Grafana dashboards for metrics, logs, and traces
- Configure the stack for both local testing and production deployments
- Visualize telemetry data in Grafana

Let me start by showing you what we're working with."

**[Action: Open file explorer, show project structure]**

```bash
# Show project structure
tree -L 2 chart/
# or
ls -la chart/
```

**Narration:**
"As you can see, we have two Helm charts:
- `observability-stack` - For local testing only, deploys the complete observability infrastructure
- `dm-nkp-gitops-custom-app` - The application chart that deploys app-specific CRs

This separation is important because in production, platform services are pre-deployed by the platform team, and applications only deploy app-specific custom resources."

---

### Segment 2: Architecture Explanation (3 minutes)

**[Screen: Draw diagram or show architecture diagram]**

**Narration:**
"Let me explain the architecture. We have:

1. **Application** - A Go application instrumented with OpenTelemetry SDK
   - Exports metrics, logs, and traces via OTLP (gRPC/HTTP)
   
2. **OpenTelemetry Collector** - The central collection point
   - Receives telemetry via OTLP
   - Processes and routes to:
     - **Prometheus** (for metrics) - via Prometheus exporter
     - **Loki** (for logs) - via Loki exporter
     - **Tempo** (for traces) - via OTLP exporter
   
3. **Grafana** - Visualization layer
   - Three dashboards: Metrics, Logs, and Traces
   - Reads from Prometheus, Loki, and Tempo

Now, for deployment:
- **Local Testing**: We deploy everything including the observability stack
- **Production**: Platform services are pre-deployed, application only deploys CRs"

**[Screen: Show architecture diagram from docs]**

**Narration:**
"This separation ensures that in production, you're not deploying infrastructure with your application - the platform team handles that. Your application chart only deploys app-specific resources like ServiceMonitor and Grafana Dashboard ConfigMaps."

---

### Segment 3: Prerequisites Setup (2 minutes)

**[Screen: Terminal showing prerequisites check]**

**Narration:**
"Before we start, let's check our prerequisites. We need:
- Go 1.25+
- Docker running
- kubectl installed
- kind for local Kubernetes
- helm for Helm charts
- And optionally, curl for making requests"

**[Action: Run checks]**

```bash
# Check prerequisites
go version
docker --version
kubectl version --client
kind version
helm version
curl --version
```

**Narration:**
"All prerequisites are installed. If you don't have these, I'll add links in the description. Now let's proceed to the demo!"

---

### Segment 4: Local Testing Demo (5 minutes)

**[Screen: Terminal - Step 1: Clone/Setup]**

**Narration:**
"For local testing, we'll deploy the complete observability stack and then the application. Let's start!"

#### Step 1: Build Application (30 seconds)

**[Action: Build application]**

```bash
# Build the application
make clean
make deps
make build

# Verify binary
ls -lh bin/dm-nkp-gitops-custom-app
```

**Narration:**
"Great! The application is built. You can see it's ready at `bin/dm-nkp-gitops-custom-app`."

#### Step 2: Run Unit Tests (30 seconds)

**[Action: Run tests]**

```bash
# Run unit tests
make unit-tests
```

**Narration:**
"Tests are passing with 100% coverage. Perfect!"

#### Step 3: Deploy Observability Stack (1.5 minutes)

**[Action: Deploy observability stack]**

```bash
# Deploy observability stack (LOCAL TESTING ONLY)
./scripts/setup-observability-stack.sh

# Or manually:
helm install observability-stack ./chart/observability-stack \
  --namespace observability \
  --create-namespace \
  --wait
```

**[Action: Check pods]**

```bash
# Wait for pods to be ready
kubectl get pods -n observability -w

# Show services
kubectl get svc -n observability
```

**Narration:**
"Perfect! The observability stack is deployed. You can see:
- OpenTelemetry Collector
- Prometheus
- Grafana Loki
- Grafana Tempo
- Grafana

All services are running in the `observability` namespace. Notice this is marked as LOCAL TESTING ONLY - we'll see why in production deployment."

#### Step 4: Deploy Application with Dashboards (1.5 minutes)

**[Action: Deploy application]**

```bash
# Deploy application with local testing values
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  -f ./chart/dm-nkp-gitops-custom-app/values-local-testing.yaml

# Wait for application
kubectl wait --for=condition=ready pod -l app=dm-nkp-gitops-custom-app --timeout=2m

# Check application pods
kubectl get pods -l app=dm-nkp-gitops-custom-app

# Check deployed CRs
kubectl get servicemonitor -n observability
kubectl get configmap -n observability -l grafana_dashboard=1
```

**Narration:**
"Excellent! The application is deployed. Notice two important things:
1. **ServiceMonitor** - This configures Prometheus to scrape metrics from the OTel Collector's Prometheus endpoint
2. **Grafana Dashboard ConfigMaps** - Three dashboards for metrics, logs, and traces

These are app-specific Custom Resources that reference the pre-deployed observability services."

#### Step 5: Generate Traffic (1 minute)

**[Action: Generate traffic]**

```bash
# Port-forward to application
kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080 &

# Generate traffic
for i in {1..50}; do
  curl http://localhost:8080/
  curl http://localhost:8080/health
  curl http://localhost:8080/ready
  sleep 0.2
done

# Verify telemetry export
kubectl logs -n default -l app=dm-nkp-gitops-custom-app | grep -i otel | tail -5
```

**Narration:**
"Great! We've generated traffic and the application is exporting telemetry to the OTel Collector. You can see in the logs that OpenTelemetry is initialized and exporting data."

---

### Segment 5: Production Deployment Demo (3 minutes)

**[Screen: Show production values file]**

**Narration:**
"Now let's see how this works in production. Remember, in production, platform services are pre-deployed by the platform team. The application chart only deploys app-specific CRs."

#### Show Production Configuration (1 minute)

**[Action: Show production values]**

```bash
# Show production values
cat chart/dm-nkp-gitops-custom-app/values-production.yaml
```

**Narration:**
"Notice in the production values:
- OTel Collector endpoint references the pre-deployed platform service: `otel-collector.observability.svc.cluster.local:4317`
- ServiceMonitor references the platform namespace where Prometheus Operator is deployed
- Grafana dashboards reference the platform namespace where Grafana is deployed

All platform service references are configurable via Helm values."

#### Production Deployment (1 minute)

**[Action: Show production deployment command]**

```bash
# Production deployment (platform services pre-deployed)
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  -f ./chart/dm-nkp-gitops-custom-app/values-production.yaml \
  --set grafana.dashboards.namespace=observability \
  --set monitoring.serviceMonitor.otelCollector.namespace=observability \
  --set monitoring.serviceMonitor.otelCollector.selectorLabels.app.kubernetes.io/name=opentelemetry-collector
```

**Narration:**
"In production, we only deploy the application chart. The observability stack is already running, managed by the platform team. Our application chart:
- Deploys the application
- Deploys ServiceMonitor CR that references the pre-deployed OTel Collector
- Deploys Grafana Dashboard ConfigMaps that reference the pre-deployed Grafana

This is the correct pattern for production deployments!"

#### Verify CRs Reference Platform Services (1 minute)

**[Action: Show ServiceMonitor]**

```bash
# Show ServiceMonitor referencing platform services
kubectl get servicemonitor -n observability -l app=dm-nkp-gitops-custom-app -o yaml | grep -A 10 "namespaceSelector"

# Show dashboard ConfigMaps
kubectl get configmap -n observability -l grafana_dashboard=1 -o yaml | grep -A 5 "metadata:"
```

**Narration:**
"As you can see, the ServiceMonitor references the platform namespace where the OTel Collector is deployed, and the dashboards are deployed to the Grafana namespace. This is exactly how production deployments work!"

---

### Segment 6: Dashboard Walkthrough (3 minutes)

**[Screen: Switch to Grafana UI]**

**Narration:**
"Now let's see the dashboards in action! Let me port-forward to Grafana and show you all three dashboards."

#### Access Grafana (30 seconds)

**[Action: Port-forward and access Grafana]**

```bash
# Port-forward to Grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80

# Open browser (or show in terminal)
# http://localhost:3000
# Username: admin
# Password: admin
```

**Narration:**
"Grafana is now accessible. I've logged in with the default credentials."

#### Metrics Dashboard (1 minute)

**[Action: Navigate to Metrics Dashboard]**

**Narration:**
"Let's check out the Metrics Dashboard first. Navigate to Dashboards → Browse.

Here we have:
- **HTTP Request Rate** - Shows requests per second over time
- **Active HTTP Connections** - A gauge showing current active connections
- **HTTP Request Duration Percentiles** - p50, p95, p99, and average duration
- **HTTP Response Size** - Distribution of response sizes
- **HTTP Requests by Method and Status** - Breakdown by HTTP method and status code
- **Business Metrics** - Custom business metrics table

All these metrics are being scraped from the OTel Collector's Prometheus endpoint, which received them from our application via OTLP!"

#### Logs Dashboard (1 minute)

**[Action: Navigate to Logs Dashboard]**

**Narration:**
"Now let's look at the Logs Dashboard. This shows:
- **Application Logs Stream** - Real-time log streaming from our application
- **Log Volume** - Logs per minute over time
- **Log Levels** - Breakdown by INFO, WARN, and ERROR
- **Error Logs** - Filtered error log stream

These logs are being collected by the OTel Collector and forwarded to Loki, which Grafana queries to display."

#### Traces Dashboard (1 minute)

**[Action: Navigate to Traces Dashboard]**

**Narration:**
"Finally, let's see the Traces Dashboard. This displays:
- **Trace Search** - Search traces by service name
- **Trace Rate** - Traces per second over time
- **Trace Duration Distribution** - Duration histogram
- **Traces by HTTP Route** - Breakdown by route
- **Traces by HTTP Status Code** - Breakdown by status code

These traces are being sent from our application to the OTel Collector, which forwards them to Tempo. Grafana queries Tempo to display the distributed traces."

**[Action: Click on a trace to show trace details]**

**Narration:**
"You can click on any trace to see the full trace details, including spans, timing, and attributes. This is incredibly powerful for debugging distributed systems!"

---

### Segment 7: Troubleshooting & Tips (1 minute)

**[Screen: Show common issues and solutions]**

**Narration:**
"Before we wrap up, let me share some troubleshooting tips:"

#### Common Issues (30 seconds)

**[Action: Show troubleshooting commands]**

```bash
# Check if dashboards are deployed
kubectl get configmap -n observability -l grafana_dashboard=1

# Check ServiceMonitor
kubectl get servicemonitor -n observability -l app=dm-nkp-gitops-custom-app

# Check Prometheus targets
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090/targets

# Check OTel Collector logs
kubectl logs -n observability -l component=otel-collector
```

**Narration:**
"If dashboards don't appear, check:
1. ConfigMaps exist with label `grafana_dashboard=1`
2. Grafana dashboard discovery is configured
3. ServiceMonitor matches OTel Collector service labels

For more troubleshooting, check the documentation!"

#### Tips (30 seconds)

**Narration:**
"Pro tips:
1. **Local Testing**: Always use the observability-stack chart for local development
2. **Production**: Only deploy the application chart - platform services are pre-deployed
3. **Configuration**: Update Helm values to match your platform's service names and namespaces
4. **Dashboards**: Dashboards are automatically discovered by Grafana if configured correctly
5. **ServiceMonitor**: Ensure selector labels match your platform's OTel Collector service labels"

---

### Segment 8: Conclusion & Resources (1 minute)

**[Screen: Show repository and documentation links]**

**Narration:**
"To summarize what we've covered:
- ✅ Complete OpenTelemetry observability stack setup
- ✅ Grafana dashboards for metrics, logs, and traces
- ✅ Separate charts for local testing vs production
- ✅ App-specific CRs that reference pre-deployed platform services
- ✅ Full end-to-end demo with working dashboards

**Key Takeaways:**
1. Observability stack is separate and marked as LOCAL TESTING ONLY
2. Application chart deploys only app-specific CRs
3. All platform service references are configurable
4. Dashboards are automatically deployed as ConfigMaps

**Resources:**
- Repository: [GitHub link]
- Documentation: Check the `docs/` folder for complete guides
- Quick Start: See [docs/OPENTELEMETRY_QUICK_START.md](OPENTELEMETRY_QUICK_START.md)
- E2E Tests: Run `make e2e-tests`

If you found this helpful, please like and subscribe! Questions? Drop them in the comments below.

Thanks for watching, and happy observability! 🚀"

**[Screen: Show end screen with links and subscribe button]**

---

## Production Tips for Recording

### Screen Recording Setup

1. **Resolution**: Record in 1920x1080 (Full HD) or higher
2. **Frame Rate**: 30 FPS minimum, 60 FPS preferred
3. **Audio**: Use a good microphone, record in a quiet environment
4. **Cursor**: Make cursor visible and smooth (use a tool like Mouse Locator)
5. **Font Size**: Increase terminal font size for better readability (18-20pt)

### Terminal Setup

```bash
# Use a readable color scheme (Solarized Dark, Dracula, etc.)
# Increase font size
# Use larger terminal window (at least 100 columns x 40 rows)
# Clear terminal before each section
```

### Editing Tips

1. **Cut Dead Time**: Remove pauses, loading times, typos
2. **Add Transitions**: Smooth transitions between sections
3. **Add Annotations**: Highlight important commands or outputs
4. **Add Text Overlays**: Show key points, links, commands
5. **Speed Up**: Speed up long build/deployment processes (2x speed)

### YouTube Optimization

**Title**:
"Complete OpenTelemetry Observability Stack with Grafana Dashboards - Kubernetes Full Demo"

**Description** (use this template):
```markdown
Complete walkthrough of an OpenTelemetry-based observability stack with Grafana dashboards for metrics, logs, and traces in Kubernetes.

📚 What You'll Learn:
- OpenTelemetry Collector setup
- Prometheus, Loki, and Tempo integration
- Grafana dashboards deployment
- Local testing vs production deployment patterns
- App-specific Custom Resources (ServiceMonitor, Dashboards)

🔗 Resources:
- GitHub Repository: [your-repo-url]
- Documentation: [docs-url]
- Quick Start Guide: [quick-start-url]

📋 Chapters:
00:00 Introduction
02:00 Architecture Overview
05:00 Prerequisites
07:00 Local Testing Demo
12:00 Production Deployment
15:00 Dashboard Walkthrough
18:00 Troubleshooting Tips
19:00 Conclusion

💻 Prerequisites:
- Go 1.25+
- Docker
- kubectl
- kind
- helm
- curl

📦 Commands Used:
[Include key commands from the video]

#OpenTelemetry #Kubernetes #Grafana #Observability #DevOps #Prometheus #Loki #Tempo
```

**Tags**:
```
OpenTelemetry, Kubernetes, Grafana, Observability, Prometheus, Loki, Tempo, DevOps, SRE, Monitoring, Logging, Tracing, Helm Charts, Kind, Kubernetes Tutorial, OpenTelemetry Tutorial, Grafana Tutorial, Full Stack Observability
```

**Thumbnail Ideas**:
- Screenshot of Grafana dashboard showing all three panels (Metrics, Logs, Traces)
- Architecture diagram with "OpenTelemetry + Grafana" overlay
- Terminal showing successful deployment with "Complete Setup" text

---

## Alternative: Quick Demo Version (5-7 minutes)

If you want a shorter version:

1. **Quick Intro** (30 sec) - What we're building
2. **Architecture** (1 min) - Quick diagram
3. **Deploy Everything** (2 min) - Single command deployment
4. **Show Dashboards** (2 min) - Quick walkthrough
5. **Conclusion** (30 sec) - Links and resources

**Single Command Demo**:
```bash
# One-liner to deploy everything for demo
./scripts/setup-observability-stack.sh && \
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  -f ./chart/dm-nkp-gitops-custom-app/values-local-testing.yaml && \
kubectl port-forward -n observability svc/prometheus-grafana 3000:80
```

---

## Additional Recording Scenarios

### Scenario A: Troubleshooting Focused Video

If you want to focus on common issues:
- Show common mistakes (combining charts, wrong selectors)
- Show how to troubleshoot ServiceMonitor
- Show how to verify dashboard discovery
- Show how to debug OTel Collector

### Scenario B: Production Setup Focused Video

If focusing on production:
- Show how platform team deploys observability stack
- Show how application team references platform services
- Show configuration for different platforms
- Show GitOps workflow

### Scenario C: Dashboard Customization Video

If focusing on dashboards:
- Show how to customize dashboard queries
- Show how to add new panels
- Show how to create custom dashboards
- Show dashboard best practices

---

## Video Checklist

Before publishing, ensure:
- [ ] All commands work and are visible
- [ ] Audio is clear and consistent
- [ ] Video quality is good (1080p+)
- [ ] Chapters are added to YouTube
- [ ] Description includes all links and resources
- [ ] Thumbnail is eye-catching
- [ ] Tags are relevant
- [ ] End screen includes subscribe button
- [ ] Cards added for related videos/content

---

This script should give you everything you need to record a comprehensive YouTube video! Good luck! 🎬
