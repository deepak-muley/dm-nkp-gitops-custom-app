# The Complete Guide to Kubernetes Observability: Metrics, Logs & Traces for Your App

*From zero to full observability — understanding the options, dependencies, and data flow*

---

## TL;DR

Adding observability (metrics, logs, traces) to a Kubernetes app seems simple until you realize there are **multiple ways to collect each signal**, platform dependencies you may not control, and configuration that can lead to duplicate data or missing telemetry.

This guide walks you through:

- ✅ What you need to install (and what's often pre-installed)
- ✅ The two major approaches to log collection
- ✅ How data flows from your app to Grafana
- ✅ A reference Go implementation you can clone

🔗 **GitHub**: [deepak-muley/dm-nkp-gitops-custom-app](https://github.com/deepak-muley/dm-nkp-gitops-custom-app)

---

## The Big Picture: What Are We Building?

When we talk about "observability," we mean three pillars:

**Metrics** — Numbers over time (request count, latency, CPU usage)

**Logs** — Text records of events (errors, info messages, debug output)

**Traces** — Request journeys across services (what called what, how long each step took)

The goal is to get all three into **Grafana**, where you can correlate them to debug issues.

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         YOUR APPLICATION                                │
│                                                                         │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                │
│  │   Metrics    │   │    Logs      │   │   Traces     │                │
│  │ (OTel SDK)   │   │  (stdout +   │   │ (OTel SDK)   │                │
│  │              │   │   OTel SDK)  │   │              │                │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘                │
│         │                  │                  │                         │
│         └──────────────────┼──────────────────┘                         │
│                            │                                            │
│                      OTLP (gRPC :4317)                                  │
└────────────────────────────┼────────────────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
┌─────────────────────────┐   ┌─────────────────────────┐
│   OpenTelemetry         │   │   Logging Operator      │
│   Collector             │   │   (Fluent Bit)          │
│                         │   │                         │
│   Receives: OTLP        │   │   Collects: stdout/     │
│   Exports to:           │   │   stderr from ALL pods  │
│   - Prometheus          │   │                         │
│   - Loki (OTLP)         │   │   Exports to: Loki      │
│   - Tempo               │   │                         │
└──────────┬──────────────┘   └──────────┬──────────────┘
           │                             │
           └──────────────┬──────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           BACKENDS                                       │
│                                                                          │
│  ┌───────────────┐   ┌───────────────┐   ┌───────────────┐              │
│  │  Prometheus   │   │    Loki       │   │    Tempo      │              │
│  │  (Metrics)    │   │   (Logs)      │   │  (Traces)     │              │
│  └───────┬───────┘   └───────┬───────┘   └───────┬───────┘              │
│          │                   │                   │                       │
│          └───────────────────┼───────────────────┘                       │
│                              ▼                                           │
│                      ┌───────────────┐                                   │
│                      │    Grafana    │                                   │
│                      │  (Dashboard)  │                                   │
│                      └───────────────┘                                   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🧩 The Dependency Stack: What Needs to Be Installed?

Here's every component you need, organized by who typically installs it:

### Platform Team (Pre-installed in Production)

These are usually installed cluster-wide by your platform/infrastructure team.

> 💡 **Nutanix NKP Users**: If you're running on **Nutanix Kubernetes Platform (NKP)**, all these platform apps are available in the **NKP Application Catalog**. Your platform team can enable, configure, and upgrade them with **one click** — no manual Helm installs required. This includes cert-manager, Traefik, Logging Operator, and the full observability stack (Prometheus, Grafana, Loki).

**cert-manager** — Manages TLS certificates automatically

- Handles Let's Encrypt integration
- Auto-renews certificates before expiry
- Required for HTTPS on your services

**Traefik (or another Ingress Controller)** — Routes external traffic into the cluster

- Acts as the Gateway
- Terminates TLS
- Routes requests to services

**Gateway API CRDs** — Modern replacement for Ingress

- Standard Kubernetes API for routing
- More expressive than Ingress
- Works with Traefik, Envoy, etc.

**MetalLB** — Load balancer for bare-metal clusters

- Assigns external IPs to LoadBalancer services
- Required if not running on cloud (AWS/GCP/Azure have built-in LBs)

**Logging Operator** — Collects logs from all pods automatically

- Deploys Fluent Bit as DaemonSet
- No code changes needed in your app
- Sends to Loki

### App Team (You Install for Your App)

**OpenTelemetry Collector** — Central telemetry router

- Receives OTLP from your app
- Fans out to Prometheus, Loki, Tempo
- Configurable pipelines

**Prometheus** — Time-series metrics database

- Stores metrics
- Query via PromQL
- Usually via kube-prometheus-stack Helm chart

**Loki** — Log aggregation system

- Stores logs (like Prometheus but for logs)
- Query via LogQL
- Version 3.0+ has native OTLP support

**Tempo** — Distributed tracing backend

- Stores traces
- Integrates with Grafana for visualization

**Grafana** — Visualization and dashboards

- Connects to all three backends
- Pre-built dashboards
- Explore mode for ad-hoc queries

---

## 🔀 The Two Paths for Log Collection

This is where things get confusing. There are **two completely different ways** to get logs into Loki:

### Path 1: Logging Operator (Automatic)

```
┌───────────────────┐
│  Your App         │
│  (any language)   │
│                   │
│  log.Printf(...)  │
│        │          │
│        ▼          │
│     stdout        │
└────────┬──────────┘
         │
         │ (Fluent Bit reads container logs)
         ▼
┌───────────────────┐
│  Logging Operator │
│  (Fluent Bit      │
│   DaemonSet)      │
└────────┬──────────┘
         │
         │ HTTP Push
         ▼
┌───────────────────┐
│       Loki        │
└───────────────────┘
```

**How it works:**

- Fluent Bit runs on every node
- Reads `/var/log/containers/*.log` (where Kubernetes writes stdout/stderr)
- Automatically collects logs from ALL pods
- No code changes required

**Labels you get:**

- `namespace`, `pod`, `container`
- `app_kubernetes_io_name` (from pod labels)

**When to use:**

- Your platform team already runs Logging Operator
- You don't want to modify application code
- You want consistent log collection across all apps

---

### Path 2: OpenTelemetry SDK (Explicit)

```
┌───────────────────────────────────┐
│  Your App (Go, Java, Python...)   │
│                                   │
│  // Using OTel SDK                │
│  telemetry.LogInfo(ctx, "msg")    │
│        │                          │
│        ▼                          │
│  ┌──────────────┐                 │
│  │  OTel SDK    │                 │
│  │  (OTLP)      │                 │
│  └──────┬───────┘                 │
└─────────┼─────────────────────────┘
          │
          │ OTLP gRPC
          ▼
┌───────────────────┐
│  OTel Collector   │
└────────┬──────────┘
         │
         │ OTLP HTTP
         ▼
┌───────────────────┐
│   Loki (3.0+)     │
└───────────────────┘
```

**How it works:**

- You instrument your code with OpenTelemetry SDK
- Logs are sent via OTLP protocol
- OTel Collector forwards to Loki's OTLP endpoint

**Labels you get:**

- `service_name`
- `severity_text` (INFO, ERROR, WARN)
- `trace_id` (enables log-to-trace correlation!)

**When to use:**

- You want trace correlation (click from log → see trace)
- You're already using OTel for metrics/traces
- You want structured logging with rich attributes

---

### ⚠️ Warning: Don't Enable Both

If both paths are active, you get **duplicate logs** in Loki:

```
Application
├── stdout → Fluent Bit → Loki  [Copy #1]
└── OTLP → OTel Collector → Loki  [Copy #2]

Result: 2x storage cost + confusion
```

**Solution:** Disable log collection in OTel Collector when Logging Operator is present:

```yaml
# values.yaml
otel-collector:
  logs:
    enabled: false  # Let Logging Operator handle it
```

---

## 🔐 TLS with Let's Encrypt

For production, you'll want HTTPS. Here's how cert-manager + Let's Encrypt works:

```
┌──────────────────────────────────────────────────────────────────────┐
│                     How cert-manager Works                           │
│                                                                      │
│  1. You create a Certificate resource                                │
│  2. cert-manager contacts Let's Encrypt                              │
│  3. Let's Encrypt issues HTTP-01 challenge                           │
│  4. cert-manager responds, proves domain ownership                   │
│  5. Let's Encrypt issues certificate (valid 90 days)                 │
│  6. cert-manager stores cert in Kubernetes Secret                    │
│  7. Gateway/Ingress uses the Secret for TLS                          │
│  8. cert-manager auto-renews before expiry                           │
└──────────────────────────────────────────────────────────────────────┘
```

**Key facts about Let's Encrypt:**

- **100% FREE** — No paid tier exists
- **Automated** — No manual certificate management
- **Trusted** — All major browsers trust it
- **Short-lived** — 90-day certs, auto-renewed

---

## 💻 Code Walkthrough

Here's how the reference implementation generates telemetry:

### 1. Application Entry Point

```go
// cmd/app/main.go
func main() {
    // Initialize all telemetry
    telemetry.InitializeLogger()
    telemetry.InitializeTracer()
    metrics.Initialize()
    
    // Create and start HTTP server
    srv := server.New(port)
    srv.Start()
}
```

### 2. Metrics Instrumentation

```go
// internal/metrics/metrics.go
RequestCounter, _ = meter.Int64Counter(
    "http_requests_total",
    metric.WithDescription("Total HTTP requests"),
)

RequestDuration, _ = meter.Float64Histogram(
    "http_request_duration_seconds",
    metric.WithDescription("Request duration"),
)
```

### 3. HTTP Handler with Traces

```go
// internal/server/server.go
func handleRoot(w http.ResponseWriter, r *http.Request) {
    ctx := r.Context()
    
    // Create trace span
    ctx, span := tracer.Start(ctx, "business.logic")
    defer span.End()
    
    // Log with trace context
    telemetry.LogInfo(ctx, "Processing request")
    
    // Update metrics
    metrics.IncrementRequestCounter()
    
    w.Write([]byte(`{"message": "Hello"}`))
}
```

### 4. Auto-instrumented HTTP Server

```go
// Wrap entire server with OTel middleware
otelHandler := otelhttp.NewHandler(mux, "http-server")
```

This automatically creates spans for every HTTP request with method, URL, status code, and duration.

---

## 🚀 Quick Start

### Option 1: Full Demo (Recommended)

```bash
git clone https://github.com/deepak-muley/dm-nkp-gitops-custom-app.git
cd dm-nkp-gitops-custom-app

# One command deploys everything
./scripts/e2e-demo-otel.sh

# Access Grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80
# Open http://localhost:3000 (admin/admin)
```

### Option 2: Step by Step

```bash
# 1. Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

# 2. Install Traefik with Gateway API
helm install traefik traefik/traefik \
  --namespace traefik-system --create-namespace \
  --set providers.kubernetesGateway.enabled=true

# 3. Install observability stack
helm install observability ./chart/observability-stack \
  --namespace observability --create-namespace

# 4. Deploy your app
helm install myapp ./chart/dm-nkp-gitops-custom-app \
  --namespace default
```

---

## 📁 Project Structure

```
├── cmd/app/main.go              # Entry point
├── internal/
│   ├── metrics/metrics.go       # OTel metrics setup
│   ├── server/server.go         # HTTP handlers
│   └── telemetry/               # Logger & tracer
├── chart/
│   ├── dm-nkp-gitops-custom-app/    # App Helm chart
│   └── observability-stack/         # OTel + backends
├── manifests/
│   ├── cert-manager/            # TLS resources
│   └── gateway-api/             # HTTPRoute, Gateway
└── scripts/
    └── e2e-demo-otel.sh         # One-click demo
```

---

## 🎯 Decision Guide: Which Approach Should You Use?

### For Logs

**Use Logging Operator (Fluent Bit) when:**

- Platform team already runs it
- You have legacy apps that just log to stdout
- You want zero code changes

**Use OpenTelemetry SDK when:**

- You need trace-log correlation
- You want structured logs with custom attributes
- You're greenfield and can instrument from scratch

**Hybrid approach:**

- Use OTel SDK for new instrumented apps
- Let Logging Operator catch legacy apps
- Configure to avoid duplicates

### For Metrics & Traces

**Always use OpenTelemetry SDK** — It's the CNCF standard and gives you vendor-neutral instrumentation.

---

## 🔗 Key Resources

- **[Full Documentation](https://github.com/deepak-muley/dm-nkp-gitops-custom-app/tree/main/docs)**
- **[Duplicate Log Collection Guide](https://github.com/deepak-muley/dm-nkp-gitops-custom-app/blob/main/docs/DUPLICATE_LOG_COLLECTION.md)**
- **[Let's Encrypt Setup](https://github.com/deepak-muley/dm-nkp-gitops-custom-app/blob/main/docs/lets-encrypt-gateway-api-setup.md)**
- **[Troubleshooting](https://github.com/deepak-muley/dm-nkp-gitops-custom-app/blob/main/docs/TROUBLESHOOTING.md)**

---

## Summary: The Observability Checklist

**Platform Dependencies (verify with your platform team):**

- [ ] cert-manager installed
- [ ] Traefik or other Gateway controller
- [ ] Gateway API CRDs
- [ ] MetalLB (for bare-metal)
- [ ] Logging Operator (if using)

**Your App Needs:**

- [ ] OpenTelemetry SDK instrumentation
- [ ] Environment variables for OTLP endpoint
- [ ] Helm chart with ServiceMonitor (for Prometheus)

**Observability Stack:**

- [ ] OpenTelemetry Collector
- [ ] Prometheus
- [ ] Loki (3.0+ for OTLP)
- [ ] Tempo
- [ ] Grafana with datasources configured

**Avoid:**

- [ ] Duplicate log collection (OTel + Logging Operator)
- [ ] Missing trace context in logs
- [ ] Unsigned container images in production

---

*Clone the repo, run the demo, and adapt it for your own services!*

**Author**: Deepak Muley  
**License**: Apache 2.0
