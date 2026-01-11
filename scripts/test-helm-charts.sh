#!/bin/bash
# Script to test Helm chart rendering for both observability stack and application charts

set -euo pipefail

echo "Testing Helm Chart Rendering..."
echo "=================================="
echo ""

# Test observability-stack chart
echo "1. Testing observability-stack chart (LOCAL TESTING ONLY)..."
if [ -f "chart/observability-stack/Chart.yaml" ]; then
  helm template observability-stack chart/observability-stack \
    --namespace observability \
    > /tmp/observability-stack-rendered.yaml
  echo "✓ observability-stack chart renders successfully"
  echo "  Rendered YAML: /tmp/observability-stack-rendered.yaml"
else
  echo "✗ observability-stack chart not found"
fi

echo ""

# Test application chart
echo "2. Testing application chart..."
if [ -f "chart/dm-nkp-gitops-custom-app/Chart.yaml" ]; then
  helm template dm-nkp-gitops-custom-app chart/dm-nkp-gitops-custom-app \
    --namespace default \
    --set opentelemetry.enabled=true \
    --set grafana.dashboards.enabled=true \
    --set monitoring.serviceMonitor.enabled=true \
    > /tmp/app-chart-rendered.yaml
  echo "✓ Application chart renders successfully"
  echo "  Rendered YAML: /tmp/app-chart-rendered.yaml"
  
  # Check if dashboards are included
  if grep -q "grafana-dashboard" /tmp/app-chart-rendered.yaml; then
    echo "✓ Grafana dashboards are included in rendered chart"
  else
    echo "⚠ Warning: Grafana dashboards may not be included"
  fi
  
  # Check if ServiceMonitor is included
  if grep -q "ServiceMonitor" /tmp/app-chart-rendered.yaml; then
    echo "✓ ServiceMonitor is included in rendered chart"
  else
    echo "⚠ Warning: ServiceMonitor may not be included"
  fi
else
  echo "✗ Application chart not found"
fi

echo ""
echo "=================================="
echo "Helm Chart Testing Complete!"
echo ""
echo "To validate rendered YAML:"
echo "  kubectl apply --dry-run=client -f /tmp/app-chart-rendered.yaml"
echo ""
