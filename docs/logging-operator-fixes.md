# Logging Operator Installation Fixes

## Issues Found and Fixed

### 1. Logging Operator Configuration Error

**Problem**: Logging Operator was showing "current config is invalid" errors.

**Root Cause**: The Logging resource was using deprecated `fluentbit` and `fluentd` fields in the spec.

**Fix**: Removed deprecated fields from Logging spec:

```yaml
apiVersion: logging.banzaicloud.io/v1beta1
kind: Logging
metadata:
  name: default
  namespace: logging
spec:
  controlNamespace: logging
```

### 2. FluentBitAgent Resource

**Status**: FluentBitAgent CRD exists but resource creation may need cluster-scope or different approach.

**Note**: The Logging Operator should automatically create FluentBit/FluentD pods when Flow and Output resources are properly configured. The Flow resource references the Output, which should trigger DaemonSet creation.

### 3. Dashboard for Logging Operator Logs

**Created**: `grafana/dashboard-loki-operator.json` - Dashboard specifically for viewing logs collected by Logging Operator (stdout/stderr logs).

**Added to script**: Dashboard is now imported automatically in `e2e-demo-otel.sh`.

## Current Status

✅ **Logging Operator**: Installed and running
✅ **Logging Resource**: Created (simplified)
✅ **Output Resource**: Configured to send to Loki
✅ **Flow Resource**: Configured to collect all pod logs
✅ **Loki Dashboard**: Created and added to import list

## Next Steps

1. Wait for FluentBit DaemonSet pods to be created (triggered by Flow/Output)
2. Generate application logs to test collection
3. Verify logs appear in Loki via Grafana dashboard

## Verification Commands

```bash
# Check Logging Operator status
kubectl get pods -n logging

# Check Logging resources
kubectl get logging,output,flow -n logging

# Check for FluentBit pods (should be created automatically)
kubectl get pods -n logging -l app.kubernetes.io/name=fluentbit

# Check logs in Loki
kubectl port-forward -n observability svc/loki-loki-distributed-gateway 3100:80
curl -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={app_kubernetes_io_name="dm-nkp-gitops-custom-app"}' \
  --data-urlencode "start=$(date -u -v-15M +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000"
```
