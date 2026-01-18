# OpenTelemetry Operator Components

The OpenTelemetry Operator is a Kubernetes operator that manages the deployment and configuration of OpenTelemetry components within a Kubernetes cluster. This document describes the key components and capabilities of the operator.

## Overview

The OpenTelemetry Operator simplifies the deployment and management of OpenTelemetry Collectors and provides auto-instrumentation capabilities for applications running in Kubernetes. It uses Kubernetes Custom Resource Definitions (CRDs) to declaratively configure OpenTelemetry components.

## Core Components

### 1. OpenTelemetry Operator Controller

**Purpose**: The main operator controller that watches for OpenTelemetry Custom Resources and manages the lifecycle of OpenTelemetry Collectors.

**Responsibilities**:

- Monitors `OpenTelemetryCollector` and `Instrumentation` CRDs
- Creates, updates, and deletes OpenTelemetry Collector deployments/daemonsets/services
- Manages collector configuration and ensures it matches the desired state
- Handles operator upgrades and configuration migrations

**Namespace**: `opentelemetry-operator-system` (default)

**Pods**: `opentelemetry-operator-*`

### 2. OpenTelemetryCollector Custom Resource

**Purpose**: Defines an instance of an OpenTelemetry Collector to be deployed and managed by the operator.

**Key Features**:

- **Deployment Modes**:
  - `deployment`: Deploys collector as a Kubernetes Deployment (recommended for most use cases)
  - `daemonset`: Deploys collector as a DaemonSet (one per node, useful for node-level telemetry)
  - `sidecar`: Injects collector as a sidecar container (deprecated, use auto-instrumentation instead)
  - `statefulset`: Deploys collector as a StatefulSet (for stateful workloads)

- **Configuration**: Specifies receivers, processors, and exporters for telemetry data
- **Replicas**: Controls the number of collector instances
- **Resources**: Can set CPU/memory requests and limits
- **Service**: Automatically creates Kubernetes Services for the collector

**Example**:

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: observability
spec:
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      batch:
    exporters:
      logging:
        loglevel: info
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [logging]
  mode: deployment
  replicas: 1
```

### 3. Instrumentation Custom Resource

**Purpose**: Provides auto-instrumentation configuration for applications without requiring code changes.

**Key Features**:

- **Auto-Injection**: Automatically injects OpenTelemetry SDK libraries into pods
- **Language Support**: Supports multiple languages:
  - Java (via OpenTelemetry Java agent)
  - Node.js (via OpenTelemetry JavaScript SDK)
  - Python (via OpenTelemetry Python SDK)
  - .NET (via OpenTelemetry .NET SDK)
  - Go (via OpenTelemetry Go SDK)
  - PHP (via OpenTelemetry PHP SDK)
  - Ruby (via OpenTelemetry Ruby SDK)

- **Annotation-Based**: Uses pod annotations to trigger instrumentation:

  ```yaml
  instrumentation.opentelemetry.io/inject-java: "true"
  instrumentation.opentelemetry.io/inject-python: "true"
  ```

- **Configuration**: Can set:
  - OTLP endpoint (where to send telemetry)
  - Resource attributes (service name, version, etc.)
  - Sampler configuration
  - Exporter settings

**Example**:

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: my-instrumentation
spec:
  exporter:
    endpoint: http://otel-collector.observability.svc.cluster.local:4318
  propagators:
    - tracecontext
    - baggage
  sampler:
    argument: "1"
    type: always_on
  java:
    env:
      - name: OTEL_JAVAAGENT_DEBUG
        value: "false"
  nodejs:
    env:
      - name: NODE_OPTIONS
        value: "--require /otel-auto-instrumentation-nodejs/autoinstrumentation.js"
```

### 4. Webhook Component (Mutating and Validating)

**Purpose**: Provides dynamic admission control for OpenTelemetry resources.

**Components**:

- **Mutating Webhook**: Automatically injects sidecar containers or instrumentation libraries into pods based on annotations
- **Validating Webhook**: Validates OpenTelemetryCollector and Instrumentation CRs to ensure they meet schema requirements

**Dependencies**: Requires cert-manager (v1.8.0+) for TLS certificate management

**Certificate Management**:

- Automatically generates certificates using cert-manager for secure webhook communication
- In cert-manager v1.18.0+, the default `privateKey.rotationPolicy` changed from `Never` to `Always`
- Warning can be suppressed by explicitly setting `rotationPolicy: Always` in Certificate resources

### 5. Collector Receivers

**Purpose**: Components that receive telemetry data from various sources.

**Common Receivers**:

- **OTLP**: Receives data via OpenTelemetry Protocol (gRPC or HTTP)
- **Prometheus**: Scrapes Prometheus metrics endpoints
- **Jaeger**: Receives Jaeger-formatted traces
- **Zipkin**: Receives Zipkin-formatted traces
- **Filelog**: Reads logs from files
- **Syslog**: Receives syslog messages

### 6. Collector Processors

**Purpose**: Components that process and transform telemetry data.

**Common Processors**:

- **Batch**: Batches telemetry data before exporting (improves efficiency)
- **Resource**: Adds or modifies resource attributes (service name, version, etc.)
- **Memory Limiter**: Prevents out-of-memory situations by dropping data when limits are reached
- **Transform**: Modifies telemetry data (rename attributes, filter spans, etc.)
- **Filter**: Filters telemetry data based on conditions

### 7. Collector Exporters

**Purpose**: Components that send telemetry data to backend systems.

**Common Exporters**:

- **OTLP**: Sends data via OpenTelemetry Protocol
- **Prometheus Remote Write**: Sends metrics to Prometheus via remote write
- **Prometheus**: Exposes metrics endpoint for Prometheus scraping
- **Logging**: Logs telemetry data to stdout (useful for debugging)
- **Jaeger**: Sends traces to Jaeger
- **Zipkin**: Sends traces to Zipkin
- **Loki**: Sends logs to Loki

## Deployment Architecture

### Typical Deployment Pattern

```
┌─────────────────────────────────────────────────────────┐
│              OpenTelemetry Operator                      │
│  (Deployed in opentelemetry-operator-system namespace)  │
└─────────────────────────────────────────────────────────┘
                        │
                        │ Watches CRDs
                        ▼
┌─────────────────────────────────────────────────────────┐
│        OpenTelemetryCollector CR                        │
│  (Defines collector configuration and deployment)       │
└─────────────────────────────────────────────────────────┘
                        │
                        │ Creates
                        ▼
┌─────────────────────────────────────────────────────────┐
│        OpenTelemetry Collector Pod(s)                   │
│  - Receives: OTLP (gRPC/HTTP on ports 4317/4318)       │
│  - Processes: Batch, Resource, etc.                     │
│  - Exports: Prometheus, Tempo, Loki, etc.               │
└─────────────────────────────────────────────────────────┘
                        │
                        │ Receives telemetry from
                        ▼
┌─────────────────────────────────────────────────────────┐
│              Application Pods                           │
│  - Send metrics, traces, logs via OTLP                  │
│  - Can use auto-instrumentation (via Instrumentation CR)│
│  - Or manual SDK integration                            │
└─────────────────────────────────────────────────────────┘
```

## Integration with Observability Stack

The OpenTelemetry Operator works seamlessly with common observability backends:

### Prometheus

- **Metrics Export**: Use `prometheusremotewrite` exporter to send metrics directly to Prometheus
- **Scraping**: Use `prometheus` receiver to scrape Prometheus-formatted endpoints

### Tempo (Traces)

- **Trace Export**: Use `otlp/tempo` exporter to send traces to Tempo
- **Format**: Uses OTLP/gRPC protocol

### Loki (Logs)

- **Log Export**: Use `loki` exporter to send logs to Loki
- **Format**: Converts OTLP logs to Loki-compatible format

### Grafana

- **Visualization**: Grafana queries Prometheus (metrics), Tempo (traces), and Loki (logs)
- **Dashboards**: Pre-built dashboards available for OpenTelemetry collectors

## Benefits of Using the Operator

1. **Declarative Management**: Define collectors using Kubernetes-native CRDs
2. **Automatic Updates**: Operator handles rolling updates when collector configuration changes
3. **Auto-Instrumentation**: Inject instrumentation into applications without code changes
4. **Multi-Language Support**: Support for Java, Node.js, Python, .NET, Go, PHP, Ruby
5. **Platform Consistency**: Ensures consistent observability setup across clusters
6. **Resource Management**: Automatic resource management and scaling

## Installation

The operator is typically installed via Helm:

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace opentelemetry-operator-system \
  --create-namespace
```

## Dependencies

- **Kubernetes**: 1.19+
- **cert-manager**: 1.8.0+ (required for webhook certificates)
- **Helm**: 3.0+ (for installation)

## Common Use Cases

1. **Centralized Telemetry Collection**: Deploy a single collector instance to receive telemetry from all applications
2. **Node-Level Collection**: Use DaemonSet mode to collect telemetry at the node level
3. **Auto-Instrumentation**: Automatically instrument applications without code changes
4. **Multi-Backend Export**: Send the same telemetry to multiple backends (e.g., Prometheus and Grafana Cloud)

## Troubleshooting

### Collector Not Starting

- Check operator logs: `kubectl logs -n opentelemetry-operator-system -l app.kubernetes.io/name=opentelemetry-operator`
- Verify OpenTelemetryCollector CR status: `kubectl get opentelemetrycollector -n observability`
- Check collector pod logs: `kubectl logs -n observability -l app.kubernetes.io/managed-by=opentelemetry-operator`

### Webhook Certificate Issues

- Ensure cert-manager is installed: `kubectl get pods -n cert-manager`
- Check certificate status: `kubectl get certificates -n opentelemetry-operator-system`
- Verify cert-manager version (must be 1.8.0+)

### Config Format Issues

- In v1beta1, `spec.config` must be a YAML object, not a string
- Validate config using: `kubectl apply --dry-run=client -f <config-file>`
- Check operator logs for detailed error messages

## References

- [OpenTelemetry Operator Documentation](https://opentelemetry.io/docs/platforms/kubernetes/operator/)
- [OpenTelemetry Operator GitHub](https://github.com/open-telemetry/opentelemetry-operator)
- [Operator Helm Chart](https://github.com/open-telemetry/opentelemetry-helm-charts)
