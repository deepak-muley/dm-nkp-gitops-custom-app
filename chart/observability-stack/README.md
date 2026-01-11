# Observability Stack Chart - LOCAL TESTING ONLY

⚠️ **WARNING: This chart is for LOCAL TESTING ONLY**

## Purpose

This Helm chart deploys a complete observability stack for **local development and testing** purposes only. It includes:

- OpenTelemetry Collector
- Prometheus (via kube-prometheus-stack)
- Grafana Loki
- Grafana Tempo
- Grafana

## ⚠️ Production Deployment

**DO NOT use this chart in production K8s clusters!**

In production environments:
1. The platform team pre-deploys all observability services (OTel Collector, Prometheus, Loki, Tempo, Grafana)
2. The application Helm chart (`dm-nkp-gitops-custom-app`) deploys only **app-specific Custom Resources**:
   - ServiceMonitor (for Prometheus scraping configuration)
   - Grafana Dashboard ConfigMaps
   - Any other app-specific observability CRs

The application chart references the pre-deployed platform services via:
- Service names (e.g., `otel-collector.observability.svc.cluster.local`)
- Namespaces (e.g., `observability`)
- Configurable selectors and labels

## Local Testing

To use this chart for local testing:

```bash
# Install observability stack for local testing
helm upgrade --install observability-stack ./chart/observability-stack \
  --namespace observability \
  --create-namespace \
  --wait

# Then deploy your application
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  --set opentelemetry.enabled=true
```

## Configuration

See `values.yaml` for configuration options. This chart is meant to be simple for learning purposes.

### Log Collection Configuration

**Important**: If your platform team deploys **Logging Operator** (Fluent Bit/D), you should disable log collection in OTel Collector to avoid duplicate logs.

**Update `values.yaml`:**
```yaml
otel-collector:
  logs:
    enabled: false  # Disable if Logging Operator handles logs
```

**Or override during install:**
```bash
helm upgrade --install observability-stack ./chart/observability-stack \
  --namespace observability \
  --create-namespace \
  --set otel-collector.logs.enabled=false
```

See [DUPLICATE_LOG_COLLECTION.md](../../docs/DUPLICATE_LOG_COLLECTION.md) for detailed explanation.

## Uninstalling

```bash
helm uninstall observability-stack --namespace observability
```

## Notes

- This chart is **NOT** intended for production use
- Production clusters have these services pre-deployed by platform teams
- The application chart automatically references pre-deployed services when deployed to production
- For local testing, deploy this chart first, then deploy the application
