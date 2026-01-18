# Kind + MetalLB Limitations

## Known Issue: LoadBalancer IP Not Accessible from Host

When using MetalLB with kind clusters, **LoadBalancer IPs are NOT directly accessible from the host machine**. This is a known limitation because:

1. **Kind uses Docker network** - The kind cluster runs inside Docker containers
2. **MetalLB assigns IPs in Docker network range** - IPs like `172.31.255.200` are only routable within the Docker network
3. **Host machine can't route to Docker network IPs** - Your host's routing table doesn't know how to reach these IPs

## Solutions for Local Testing

### Option 1: Port-Forward (Simplest - Recommended)

Port-forward directly to your application service:

```bash
# Port-forward to application service
kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080

# In another terminal, access application
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/ready
```

**Pros:** Simple, always works  
**Cons:** Requires port-forward to be running, not testing Gateway/HTTPRoute

### Option 2: Port-Forward to Traefik (Tests Gateway/HTTPRoute)

Port-forward to Traefik service:

```bash
# Port-forward to Traefik
kubectl port-forward -n traefik-system svc/traefik 8080:80

# Access via hostname (add to /etc/hosts: 127.0.0.1 dm-nkp-gitops-custom-app.local)
curl http://dm-nkp-gitops-custom-app.local:8080/
```

**Note:** If Gateway status shows "Unknown", HTTPRoute may not work via Traefik. Use Option 1 instead.

### Option 3: Use NodePort (If Gateway is Working)

If your Gateway is properly configured, you can use NodePort:

```bash
# Get kind node IP
NODE_IP=$(docker inspect dm-nkp-demo-cluster-control-plane --format='{{.NetworkSettings.Networks.kind.IPAddress}}')

# Get NodePort
NODEPORT=$(kubectl get svc traefik -n traefik-system -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')

# Access via NodePort
curl -H "Host: dm-nkp-gitops-custom-app.local" http://${NODE_IP}:${NODEPORT}/
```

**Note:** This also requires Gateway to be working correctly.

### Option 4: Direct Port Mapping (kind configuration)

Configure kind cluster with port mappings:

```yaml
# kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 30080
    protocol: TCP
```

Then access via `localhost:30080` with Host header.

## Why LoadBalancer IP Doesn't Work

```
Host Machine
    ↓
    ❌ Can't route to 172.31.255.200 (Docker network IP)
    ↓
Docker Network (172.31.0.0/16)
    ↓
Kind Cluster
    ↓
MetalLB assigns 172.31.255.200 to Traefik service
```

The IP `172.31.255.200` is only routable **within the Docker network**, not from your host machine.

## Production vs Local Testing

**Production (NKP Platform):**

- ✅ MetalLB LoadBalancer IPs are **fully routable**
- ✅ DNS/ingress routes traffic to LoadBalancer IP
- ✅ HTTPRoute works via Gateway API

**Local Testing (kind):**

- ❌ MetalLB LoadBalancer IPs are **NOT routable from host**
- ✅ Use port-forward for local testing
- ⚠️ Gateway status may show "Unknown" (Traefik Gateway API integration may have issues)

## Gateway "Unknown" Status

If your Gateway shows "Unknown" status:

```bash
kubectl get gateway traefik -n traefik-system
# ADDRESS shows: <none>
# PROGRAMMED shows: Unknown
```

This means Traefik isn't recognizing the Gateway resource. Possible causes:

1. Traefik Gateway API support not fully enabled
2. GatewayClass not properly configured
3. Traefik version compatibility issue

**Workaround:** Use port-forward directly to application service (Option 1) instead of going through Traefik Gateway.

## Recommended Setup for Local Testing

For local testing with kind, **use port-forward**:

```bash
# Start port-forward in background
kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080 &

# Access application
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/ready

# Stop port-forward when done
pkill -f "kubectl port-forward"
```

This bypasses Gateway/HTTPRoute issues and directly accesses your application.

## References

- [MetalLB Documentation](https://metallb.universe.tf/)
- [Kind Limitations](https://kind.sigs.k8s.io/docs/user/loadbalancer/)
- [Traefik Gateway API Support](https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/)
