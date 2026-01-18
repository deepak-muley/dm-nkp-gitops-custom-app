# Access Instructions - LoadBalancer IP with Path-Based Routing

This document provides step-by-step instructions to access your application and observability services via LoadBalancer IP after running the e2e-demo-otel.sh script.

## Prerequisites

1. **Kind cluster is running** - Verify with: `kind get clusters`
2. **Script has completed** - Wait for `./scripts/e2e-demo-otel.sh` to finish
3. **MetalLB is installed** - Check with: `kubectl get pods -n metallb-system`

## Quick Verification

Run the verification script to get current status and access instructions:

```bash
./scripts/verify-access.sh
```

## Manual Verification Steps

### 1. Check Traefik LoadBalancer IP

```bash
kubectl get svc traefik -n traefik-system
```

You should see output like:

```
NAME      TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)        AGE
traefik   LoadBalancer   10.96.xxx.xxx   172.18.255.200  80:30080/TCP   5m
```

**Note the EXTERNAL-IP** - this is your LoadBalancer IP (e.g., `172.18.255.200`)

### 2. Check HTTPRoute Status

```bash
kubectl get httproute -n default
kubectl describe httproute -n default
```

Verify that the HTTPRoute is **Accepted** and has a parent reference to the Traefik Gateway.

### 3. Configure Hostname

Add the hostname to `/etc/hosts` file (replace `172.18.255.200` with your actual LoadBalancer IP):

```bash
echo "172.18.255.200 dm-nkp-gitops-custom-app.local" | sudo tee -a /etc/hosts
```

Verify the entry:

```bash
grep dm-nkp-gitops-custom-app.local /etc/hosts
```

## Access Methods

### Method 1: Via Hostname (Recommended)

Once `/etc/hosts` is configured, access via hostname:

```bash
# Main application
curl http://dm-nkp-gitops-custom-app.local/
curl http://dm-nkp-gitops-custom-app.local/health
curl http://dm-nkp-gitops-custom-app.local/ready

# Metrics endpoint
curl http://dm-nkp-gitops-custom-app.local/metrics
```

### Method 2: Direct LoadBalancer IP

Access directly via LoadBalancer IP with Host header:

```bash
LB_IP=$(kubectl get svc traefik -n traefik-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -H "Host: dm-nkp-gitops-custom-app.local" http://${LB_IP}/
curl -H "Host: dm-nkp-gitops-custom-app.local" http://${LB_IP}/health
curl -H "Host: dm-nkp-gitops-custom-app.local" http://${LB_IP}/ready
```

### Method 3: Path-Based Routing (Future - Observability Services)

Once observability stack HTTPRoute is configured, you'll be able to access:

```bash
LB_IP=$(kubectl get svc traefik -n traefik-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Grafana (when configured)
curl -H "Host: observability.local" http://${LB_IP}/grafana/

# Prometheus (when configured)
curl -H "Host: observability.local" http://${LB_IP}/prometheus/

# Loki (when configured)
curl -H "Host: observability.local" http://${LB_IP}/loki/
```

## Troubleshooting

### LoadBalancer IP is Pending

If `EXTERNAL-IP` shows `<pending>`:

1. **Check MetalLB pods:**

   ```bash
   kubectl get pods -n metallb-system
   ```

   All pods should be `Running`.

2. **Check IP address pool:**

   ```bash
   kubectl get ipaddresspool -n metallb-system
   kubectl describe ipaddresspool -n metallb-system
   ```

3. **Check MetalLB logs:**

   ```bash
   kubectl logs -n metallb-system -l app.kubernetes.io/name=metallb
   ```

4. **Wait a bit longer** - IP assignment can take 1-2 minutes

### HTTPRoute Not Accepted

If HTTPRoute shows as not accepted:

1. **Check Gateway status:**

   ```bash
   kubectl get gateway -n traefik-system
   kubectl describe gateway traefik -n traefik-system
   ```

2. **Verify Gateway is accepted:**
   Look for `Accepted=True` in Gateway status conditions.

3. **Check HTTPRoute parent reference:**

   ```bash
   kubectl get httproute -n default -o yaml | grep -A 5 parentRefs
   ```

### Cannot Access Application

If you can't access the application:

1. **Check application pods:**

   ```bash
   kubectl get pods -n default -l app.kubernetes.io/name=dm-nkp-gitops-custom-app
   ```

2. **Check application logs:**

   ```bash
   kubectl logs -n default -l app.kubernetes.io/name=dm-nkp-gitops-custom-app --tail=50
   ```

3. **Test direct service access:**

   ```bash
   kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080
   curl http://localhost:8080/
   ```

4. **Verify HTTPRoute backend:**

   ```bash
   kubectl describe httproute -n default | grep -A 10 backendRefs
   ```

### Fallback: Use Port-Forward

If LoadBalancer IP isn't working, use port-forward:

```bash
# Port-forward to Traefik
kubectl port-forward -n traefik-system svc/traefik 8080:80

# In another terminal, test access
curl -H "Host: dm-nkp-gitops-custom-app.local" http://localhost:8080/
```

## Expected Response

When accessing the application, you should see:

```bash
$ curl http://dm-nkp-gitops-custom-app.local/
Hello from dm-nkp-gitops-custom-app
```

Health endpoint:

```bash
$ curl http://dm-nkp-gitops-custom-app.local/health
{"status":"healthy"}
```

Ready endpoint:

```bash
$ curl http://dm-nkp-gitops-custom-app.local/ready
{"status":"ready"}
```

## Next Steps

Once access is confirmed:

1. **Generate traffic** to see metrics in Grafana
2. **Check observability dashboards** in Grafana
3. **Verify traces** are being collected in Tempo
4. **Check logs** are being collected in Loki

For more information, see:

- `./scripts/verify-access.sh` - Quick status check
- `docs/gateway-api-path-based-routing.md` - Path-based routing setup
