# Health Endpoints & Probes - Complete Explanation

## What Your App Has

Your application exposes **3 HTTP endpoints**:

1. **`/`** - Main application endpoint (returns JSON greeting)
2. **`/health`** - Liveness endpoint (tells Kubernetes if pod is alive)
3. **`/ready`** - Readiness endpoint (tells Kubernetes if pod is ready to serve traffic)

All endpoints are served on the same port (`8080` by default).

---

## How Kubernetes Probes Work

### Liveness Probe (`/health`)

**Purpose**: Tells Kubernetes "is my pod still alive and functioning?"

**What happens**:
1. Kubernetes kubelet calls `/health` **directly on the pod IP** (not through service/ingress)
2. If `/health` returns non-200 → Kubernetes kills the pod and restarts it
3. If `/health` returns 200 → Pod is considered healthy

**Your configuration** (in `deployment.yaml`):
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 10  # Wait 10s after pod starts before first check
  periodSeconds: 10        # Check every 10 seconds
```

### Readiness Probe (`/ready`)

**Purpose**: Tells Kubernetes "is my pod ready to receive traffic?"

**What happens**:
1. Kubernetes kubelet calls `/ready` **directly on the pod IP** (not through service/ingress)
2. If `/ready` returns non-200 → Pod is removed from Service endpoints (no traffic routed to it)
3. If `/ready` returns 200 → Pod is added to Service endpoints (traffic can be routed)

**Your configuration**:
```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 5   # Wait 5s after pod starts
  periodSeconds: 5         # Check every 5 seconds
```

---

## Key Concept: Direct Pod Access

**Important**: Kubernetes probes access pods **directly**, not through:

❌ **NOT through Service**  
❌ **NOT through Ingress/HTTPRoute**  
❌ **NOT through Gateway**

✅ **Directly via pod IP** (internal cluster network only)

### Visual Flow

```
Kubernetes Kubelet (on node)
    ↓
    | (Direct connection via pod IP: 10.244.x.x:8080)
    ↓
Pod Container
    ↓
/health or /ready endpoint
```

**Why direct?**
- Faster (no network hops)
- More reliable (service might be healthy but pod might not be)
- Internal only (security - health checks shouldn't be exposed externally)

---

## Do Health Endpoints Need HTTPRoute?

### Short Answer: **NO** ❌

**Reasons:**

1. **Kubernetes Probes Don't Need HTTPRoute**
   - Probes access pods directly via pod IP
   - They bypass Service, Ingress, and Gateway entirely
   - HTTPRoute is only for **external traffic** (traffic from outside the cluster)

2. **Security Best Practice**
   - Health endpoints (`/health`, `/ready`) should **NOT be exposed externally**
   - Exposing them publicly can reveal:
     - Application status (helpful for attackers)
     - Internal architecture details
     - Attack surface for DoS (flooding health endpoints)

3. **Different Use Cases**
   - **`/health`, `/ready`** → Internal Kubernetes health checks (by kubelet)
   - **`/`** → External user traffic (needs HTTPRoute for public access)

---

## What Should Be Exposed via HTTPRoute?

### ✅ Should Be Exposed (Current Setup)

**Main Application Endpoint:**
```yaml
# HTTPRoute routes this path
rules:
  - matches:
      - path:
          type: PathPrefix
          value: /              # Main app endpoint
    backendRefs:
      - name: app-service
        port: 8080
```

**Why**: This is the actual application endpoint that users/clients need to access.

### ❌ Should NOT Be Exposed (Security Best Practice)

**Health/Readiness Endpoints:**
- `/health` - Keep internal (only for Kubernetes probes)
- `/ready` - Keep internal (only for Kubernetes probes)

**Why**:
1. **Security**: Don't expose internal health status
2. **No Need**: Kubernetes probes access directly anyway
3. **Best Practice**: Health endpoints are for internal monitoring only

---

## Current Setup (Your App)

### ✅ What You Have (Correct!)

**Application Endpoints:**
```go
// internal/server/server.go
mux.HandleFunc("/", handleRoot)      // Main endpoint
mux.HandleFunc("/health", handleHealth)  // Liveness (internal)
mux.HandleFunc("/ready", handleReady)    // Readiness (internal)
```

**Kubernetes Probes:**
```yaml
# chart/dm-nkp-gitops-custom-app/templates/deployment.yaml
livenessProbe:
  httpGet:
    path: /health      # ✅ Kubernetes calls this directly
    port: http
readinessProbe:
  httpGet:
    path: /ready       # ✅ Kubernetes calls this directly
    port: http
```

**HTTPRoute:**
```yaml
# chart/dm-nkp-gitops-custom-app/templates/httproute.yaml
rules:
  - matches:
      - path:
          type: PathPrefix
          value: /              # ✅ Only main endpoint exposed
    backendRefs:
      - name: app-service
        port: 8080
```

### ✅ Your Setup is Correct!

Your current configuration is **correct and follows best practices**:
- ✅ Health endpoints exist and work
- ✅ Kubernetes probes configured correctly
- ✅ Only main endpoint (`/`) exposed via HTTPRoute
- ✅ Health endpoints kept internal (secure)

---

## When Would You Expose Health Endpoints?

### Rare Cases (Usually NOT Recommended)

**External Monitoring Tools:**
Some organizations expose `/health` for external monitoring (like Uptime Robot, Pingdom), but this is **NOT recommended** because:

1. **Security Risk**: Exposes internal state
2. **Better Alternatives**: Use Kubernetes metrics, ServiceMonitors, or internal monitoring
3. **Attack Surface**: Can be abused for DoS attacks

**If you absolutely must expose it (not recommended):**

```yaml
# HTTPRoute with separate path for health (if needed for external monitoring)
rules:
  - matches:
      - path:
          type: PathPrefix
          value: /
    backendRefs:
      - name: app-service
        port: 8080
  - matches:
      - path:
          type: Exact  # Use Exact, not PathPrefix, for security
          value: /health
    backendRefs:
      - name: app-service
        port: 8080
```

**Better Alternative**: Use Kubernetes ServiceMonitor or internal monitoring to check health without exposing it.

---

## How Kubernetes Probes Work (Detailed)

### Step-by-Step Flow

**1. Pod Starts:**
```
Pod starts → Container starts → Application starts → Endpoints available
```

**2. Initial Delay:**
```
Wait 5-10 seconds (initialDelaySeconds)
→ Allows app to fully start
```

**3. Readiness Probe Runs:**
```
Kubelet calls: http://<pod-ip>:8080/ready
→ If 200: Pod added to Service endpoints (traffic can come)
→ If non-200: Pod excluded from Service (no traffic)
```

**4. Liveness Probe Runs:**
```
Kubelet calls: http://<pod-ip>:8080/health
→ If 200: Pod is healthy (no action)
→ If non-200: Pod is killed and restarted
```

**5. Traffic Routing:**
```
External request → Gateway → HTTPRoute → Service → Pod
                              ↑
                         (Only if readiness probe passed)
```

### Visual: Complete Flow

```
External User
    ↓
Traefik Gateway (HTTPRoute)
    ↓ (HTTPRoute routes to Service)
Service
    ↓ (Service routes to pods where readinessProbe=ready)
Pod 1 (ready=true)  ✅ Gets traffic
Pod 2 (ready=false) ❌ No traffic (readiness probe failed)

BUT:

Kubernetes Kubelet
    ↓ (Direct pod IP access, bypasses Service/HTTPRoute)
Pod 1: http://10.244.x.x:8080/health  ✅ (liveness probe)
Pod 1: http://10.244.x.x:8080/ready   ✅ (readiness probe)
```

---

## Common Questions

### Q: Can I test `/health` and `/ready` manually?

**A: Yes, but from inside the cluster:**
```bash
# Port forward to service (works, but not how kubelet does it)
kubectl port-forward svc/app 8080:8080
curl http://localhost:8080/health
curl http://localhost:8080/ready

# Or exec into pod and curl localhost
kubectl exec -it <pod-name> -- curl http://localhost:8080/health

# Or access pod directly (closest to how kubelet does it)
kubectl get pod <pod-name> -o jsonpath='{.status.podIP}'
curl http://<pod-ip>:8080/health
```

### Q: Why does my HTTPRoute only have `/` path?

**A: Because that's correct!**
- Health endpoints don't need to be in HTTPRoute
- They're accessed directly by Kubernetes
- Exposing them externally is a security risk

### Q: What if I want external health checks?

**A: Use these alternatives (better than exposing `/health`):**
1. **ServiceMonitor** → Prometheus scrapes metrics
2. **Kubernetes Metrics** → Monitor pod status
3. **Internal Monitoring** → Deploy internal monitoring that checks health
4. **Keep `/health` internal** → External tools can check pod status via Kubernetes API

### Q: Should I add `/healthz` or `/healthz/ready`?

**A: Not necessary!**
- `/health` and `/ready` are standard Kubernetes convention
- Your naming is correct
- No need to change

---

## Best Practices Summary

### ✅ DO:

1. **Keep health endpoints internal** (`/health`, `/ready`)
2. **Configure livenessProbe and readinessProbe** in deployment
3. **Only expose main application endpoints** via HTTPRoute (`/`)
4. **Use different paths** for liveness (`/health`) vs readiness (`/ready`)

### ❌ DON'T:

1. **Don't expose `/health` or `/ready` via HTTPRoute** (security risk)
2. **Don't use `/healthz` or `/readyz`** (your current naming is fine)
3. **Don't route health endpoints through Gateway** (not needed)
4. **Don't make health endpoints return sensitive data**

---

## Your Current Configuration (Review)

### ✅ Application Code (Correct!)

```go
// Three endpoints, all on same port
mux.HandleFunc("/", handleRoot)     // Main app
mux.HandleFunc("/health", handleHealth)  // Liveness
mux.HandleFunc("/ready", handleReady)    // Readiness
```

### ✅ Kubernetes Deployment (Correct!)

```yaml
livenessProbe:
  httpGet:
    path: /health    # ✅ Kubernetes calls this directly
    port: http
  initialDelaySeconds: 10
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready     # ✅ Kubernetes calls this directly
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5
```

### ✅ HTTPRoute (Correct!)

```yaml
rules:
  - matches:
      - path:
          type: PathPrefix
          value: /              # ✅ Only main endpoint exposed
    backendRefs:
      - name: app-service
        port: 8080
# ✅ Health endpoints NOT exposed (correct!)
```

---

## Summary

**Your app has:**
- ✅ `/health` endpoint (liveness)
- ✅ `/ready` endpoint (readiness)
- ✅ Kubernetes probes configured correctly
- ✅ HTTPRoute exposes only main endpoint (correct!)

**Health endpoints DON'T need HTTPRoute because:**
- ✅ Kubernetes probes access pods directly (bypass HTTPRoute)
- ✅ Security best practice (don't expose health endpoints)
- ✅ They work internally without HTTPRoute

**Your current setup is correct and follows best practices!** 🎉

---

## References

- [Kubernetes Liveness and Readiness Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Kubernetes Health Check Patterns](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes)
- [Gateway API HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/)
