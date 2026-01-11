# Complete Workflow - OpenTelemetry Observability with Grafana Dashboards

## Overview

This document provides a complete workflow for deploying the application with OpenTelemetry observability and Grafana dashboards for metrics, logs, and traces.

## Architecture Flow

```
┌─────────────────────────────────────────────────────────┐
│                  APPLICATION (Go)                        │
│  ┌─────────────────────────────────────────┐            │
│  │  OpenTelemetry SDK                      │            │
│  │  ├─ Metrics → OTLP gRPC                │            │
│  │  ├─ Logs → stdout/stderr (OTLP)        │            │
│  │  └─ Traces → OTLP gRPC                 │            │
│  └─────────────────────────────────────────┘            │
└──────────────────────┬──────────────────────────────────┘
                       │ OTLP (gRPC/HTTP)
                       ▼
┌─────────────────────────────────────────────────────────┐
│      OPEN TELEMETRY COLLECTOR (Platform Service)        │
│  ┌─────────────────────────────────────────┐            │
│  │  Receivers: OTLP (gRPC/HTTP)            │            │
│  │  Processors: Batch                      │            │
│  │  Exporters:                             │            │
│  │  ├─ Prometheus (port 8889) → Metrics   │            │
│  │  ├─ Loki (/api/v1/push) → Logs         │            │
│  │  └─ Tempo (OTLP) → Traces              │            │
│  └─────────────────────────────────────────┘            │
└───┬─────────────────┬─────────────────┬────────────────┘
    │                 │                 │
    ▼                 ▼                 ▼
┌──────────┐   ┌──────────┐   ┌──────────┐
│Prometheus│   │   Loki   │   │  Tempo   │
│(Metrics) │   │  (Logs)  │   │ (Traces) │
└────┬─────┘   └────┬─────┘   └────┬─────┘
     │              │              │
     └──────────────┴──────────────┘
                    │
                    ▼
            ┌──────────────┐
            │   Grafana    │
            │(Visualization)│
            │  ├─ Metrics  │
            │  ├─ Logs     │
            │  └─ Traces   │
            └──────────────┘
```

## Deployment Workflow

### Workflow 1: Local Testing (Complete Stack)

**Purpose**: Full observability stack for local development and testing

**Steps**:

1. **Deploy Observability Stack** (LOCAL TESTING ONLY):
   ```bash
   ./scripts/setup-observability-stack.sh
   
   # Or manually:
   helm install observability-stack ./chart/observability-stack \
     --namespace observability --create-namespace --wait
   ```

2. **Verify Services are Running**:
   ```bash
   kubectl get pods -n observability
   # Should see: otel-collector, prometheus, grafana, loki, tempo
   ```

3. **Deploy Application with Dashboards**:
   ```bash
   helm install app ./chart/dm-nkp-gitops-custom-app \
     --namespace default \
     -f ./chart/dm-nkp-gitops-custom-app/values-local-testing.yaml
   ```

4. **Verify App-Specific CRs**:
   ```bash
   # Check ServiceMonitor
   kubectl get servicemonitor -n observability -l app=dm-nkp-gitops-custom-app
   
   # Check Grafana Dashboard ConfigMaps
   kubectl get configmap -n observability -l grafana_dashboard=1
   ```

5. **Access Grafana and Verify Dashboards**:
   ```bash
   kubectl port-forward -n observability svc/prometheus-grafana 3000:80
   # Open: http://localhost:3000 (admin/admin)
   # Navigate to: Dashboards → Browse
   # Should see:
   #   - dm-nkp-gitops-custom-app - Metrics
   #   - dm-nkp-gitops-custom-app - Logs
   #   - dm-nkp-gitops-custom-app - Traces
   ```

6. **Generate Test Data**:
   ```bash
   kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080
   
   # Generate traffic
   for i in {1..50}; do
     curl http://localhost:8080/
     curl http://localhost:8080/health
     curl http://localhost:8080/ready
     sleep 0.5
   done
   ```

7. **Verify Data in Dashboards**:
   - Check Metrics Dashboard → Should see HTTP request rates
   - Check Logs Dashboard → Should see application logs
   - Check Traces Dashboard → Should see distributed traces

### Workflow 2: Production Deployment (Platform Services Pre-deployed)

**Purpose**: Deploy application on production cluster where platform services are already running

**Steps**:

1. **Verify Platform Services are Available**:
   ```bash
   # Check OTel Collector
   kubectl get svc -n observability -l component=otel-collector
   
   # Check Prometheus Operator
   kubectl get crd servicemonitors.monitoring.coreos.com
   
   # Check Grafana
   kubectl get svc -n observability -l app.kubernetes.io/name=grafana
   ```

2. **Configure Application Values** (if needed):
   ```bash
   # Create production values file or update existing
   cp chart/dm-nkp-gitops-custom-app/values-production.yaml my-production-values.yaml
   
   # Edit my-production-values.yaml to match your platform:
   # - OTel Collector endpoint
   # - Service selector labels
   # - Namespaces
   ```

3. **Deploy Application**:
   ```bash
   helm install app ./chart/dm-nkp-gitops-custom-app \
     --namespace production \
     -f my-production-values.yaml \
     --set grafana.dashboards.namespace=observability \
     --set monitoring.serviceMonitor.namespace=observability
   ```

4. **Verify Deployment**:
   ```bash
   # Check application pods
   kubectl get pods -n production -l app=dm-nkp-gitops-custom-app
   
   # Check ServiceMonitor
   kubectl get servicemonitor -n observability -l app=dm-nkp-gitops-custom-app
   
   # Check Grafana Dashboard ConfigMaps
   kubectl get configmap -n observability -l grafana_dashboard=1
   ```

5. **Verify Prometheus is Scraping**:
   ```bash
   kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
   # Open: http://localhost:9090/targets
   # Should see OTel Collector target as UP
   ```

6. **Access Grafana Dashboards**:
   ```bash
   kubectl port-forward -n observability svc/prometheus-grafana 3000:80
   # Open: http://localhost:3000
   # Navigate to: Dashboards → Browse
   # Should see all three dashboards
   ```

## App-Specific Custom Resources

### What Gets Deployed by Application Chart

1. **ServiceMonitor CR** (`templates/servicemonitor-otel.yaml`)
   - Configures Prometheus to scrape OTel Collector's `/metrics` endpoint
   - References pre-deployed OTel Collector service
   - Deployed to Prometheus Operator namespace
   - Automatically discovered by Prometheus Operator

2. **Grafana Dashboard ConfigMaps** (`templates/grafana-dashboards.yaml`)
   - Metrics Dashboard ConfigMap (label: `grafana_dashboard=1`)
   - Logs Dashboard ConfigMap (label: `grafana_dashboard=1`)
   - Traces Dashboard ConfigMap (label: `grafana_dashboard=1`)
   - Deployed to Grafana namespace
   - Automatically discovered by Grafana (if dashboard discovery configured)

3. **Grafana Datasources ConfigMap** (`templates/grafana-datasources.yaml`) - Optional
   - Only if platform team hasn't pre-configured datasources
   - Configures Prometheus, Loki, and Tempo data sources
   - Default: disabled (platform usually configures)

## Configuration Reference

### Platform Service Endpoints

Configure these based on your platform's actual service names and namespaces:

```yaml
# OpenTelemetry Collector
opentelemetry:
  collector:
    endpoint: "otel-collector.observability.svc.cluster.local:4317"
    # Or: "otel-collector.platform-monitoring.svc.cluster.local:4317"

# Prometheus Operator
monitoring:
  serviceMonitor:
    namespace: "observability"  # Where Prometheus Operator is deployed
    otelCollector:
      namespace: "observability"  # Where OTel Collector is deployed
      selectorLabels:
        component: otel-collector  # Match your platform's labels
        # Or: app.kubernetes.io/name: opentelemetry-collector

# Grafana
grafana:
  dashboards:
    namespace: "observability"  # Where Grafana is deployed
```

### Example Platform Configurations

#### Example 1: Standard Platform

```yaml
opentelemetry:
  collector:
    endpoint: "otel-collector.observability.svc.cluster.local:4317"

monitoring:
  serviceMonitor:
    otelCollector:
      selectorLabels:
        component: otel-collector

grafana:
  dashboards:
    namespace: "observability"
```

#### Example 2: Custom Platform Namespace

```yaml
opentelemetry:
  collector:
    endpoint: "otel-collector.platform-monitoring.svc.cluster.local:4317"

monitoring:
  serviceMonitor:
    namespace: "platform-monitoring"
    otelCollector:
      namespace: "platform-monitoring"
      selectorLabels:
        app.kubernetes.io/name: opentelemetry-collector

grafana:
  dashboards:
    namespace: "platform-monitoring"
```

## Data Flow Verification

### Metrics Flow

```
Application → OTLP (gRPC) → OTel Collector → Prometheus Exporter (port 8889)
                                                         ↓
                                               Prometheus Scrapes
                                                         ↓
                                                    Prometheus DB
                                                         ↓
                                              Grafana Metrics Dashboard
```

**Verify**:
1. Application logs: `kubectl logs deployment/dm-nkp-gitops-custom-app | grep -i otel`
2. OTel Collector logs: `kubectl logs -n observability deployment/otel-collector`
3. Prometheus targets: `kubectl port-forward -n observability svc/prometheus 9090:9090` → `/targets`
4. Grafana Metrics Dashboard: Should show HTTP request rates and metrics

### Logs Flow

```
Application → stdout/stderr → OTel Collector → Loki (/api/v1/push)
                                                      ↓
                                                   Loki DB
                                                      ↓
                                            Grafana Logs Dashboard
```

**Verify**:
1. Application logs: `kubectl logs deployment/dm-nkp-gitops-custom-app`
2. OTel Collector logs: `kubectl logs -n observability deployment/otel-collector | grep -i loki`
3. Loki query: `kubectl port-forward -n observability svc/loki 3100:3100` → Query logs
4. Grafana Logs Dashboard: Should show application logs

### Traces Flow

```
Application → OTLP (gRPC) → OTel Collector → Tempo (OTLP)
                                                     ↓
                                                  Tempo DB
                                                     ↓
                                            Grafana Traces Dashboard
```

**Verify**:
1. Application traces: Check OTel Collector logs for trace export
2. OTel Collector logs: `kubectl logs -n observability deployment/otel-collector | grep -i tempo`
3. Tempo query: `kubectl port-forward -n observability svc/tempo 3200:3200` → Query traces
4. Grafana Traces Dashboard: Should show distributed traces

## Troubleshooting

### Dashboards Not Appearing

**Check**:
1. ConfigMaps exist: `kubectl get configmap -n observability -l grafana_dashboard=1`
2. Grafana dashboard discovery configured: `kubectl get configmap -n observability grafana-dashboard-provider`
3. Grafana logs: `kubectl logs -n observability deployment/prometheus-grafana | grep -i dashboard`

**Fix**: Manually import dashboards if automatic discovery doesn't work:
- Port-forward to Grafana
- Go to Dashboards → Import
- Upload JSON files from `grafana/` directory

### ServiceMonitor Not Discovered

**Check**:
1. ServiceMonitor exists: `kubectl get servicemonitor -n observability`
2. Prometheus Operator installed: `kubectl get crd servicemonitors.monitoring.coreos.com`
3. OTel Collector service labels match selector: `kubectl get svc -n observability -l component=otel-collector --show-labels`

**Fix**: Update selector labels in values to match your platform's OTel Collector service labels.

### No Data in Dashboards

**Metrics Dashboard**:
- Verify Prometheus is scraping: Check `/targets` endpoint
- Verify application is generating metrics: Check application logs
- Verify metric names match queries: Check dashboard queries

**Logs Dashboard**:
- Verify application is logging: `kubectl logs deployment/dm-nkp-gitops-custom-app`
- Verify OTel Collector forwards to Loki: Check OTel Collector logs
- Verify log labels match queries: Check Loki query syntax

**Traces Dashboard**:
- Verify application creates traces: Check application logs for span creation
- Verify OTel Collector forwards to Tempo: Check OTel Collector logs
- Verify service name matches: Check Tempo query for service name

## Summary

### ✅ What's Ready

1. **Grafana Dashboards**: Three complete dashboards for metrics, logs, and traces
2. **Helm Charts**: Properly separated for local testing vs production
3. **App-Specific CRs**: ServiceMonitor and Dashboard ConfigMaps
4. **Platform References**: Configurable values for pre-deployed services
5. **Enhanced Application**: Rich logs and traces throughout
6. **E2E Tests**: Updated for OpenTelemetry
7. **Documentation**: Complete guides and workflows

### 🎯 Key Points

- **Observability Stack Chart**: LOCAL TESTING ONLY - Complete stack for local development
- **Application Chart**: Production-ready - Deploys only app-specific CRs
- **Platform Services**: Pre-deployed by platform team in production
- **App CRs**: Reference pre-deployed services via configurable values
- **Dashboards**: Automatically deployed as ConfigMaps with proper labels
- **ServiceMonitor**: Configures Prometheus to scrape OTel Collector

### 🚀 Ready to Deploy!

Everything is configured and ready. Follow the deployment workflows above to deploy and verify the complete observability stack with Grafana dashboards.
