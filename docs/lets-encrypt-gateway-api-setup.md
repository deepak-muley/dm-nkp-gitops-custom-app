# Let's Encrypt Integration with Gateway API and MetalLB

## What is Let's Encrypt?

**Let's Encrypt is a FREE, automated, open Certificate Authority (CA)** that provides TLS/SSL certificates at no cost. There is no paid tier - all certificates are free.

### Key Facts About Let's Encrypt

| Aspect | Details |
|--------|---------|
| **Cost** | ✅ **100% FREE** - No paid plans exist |
| **Certificate Validity** | 90 days (auto-renewed by cert-manager) |
| **Rate Limits** | 50 certs/domain/week (prod), unlimited (staging) |
| **Trust** | Trusted by all major browsers and operating systems |
| **Automation** | Fully automated via ACME protocol |
| **Wildcard Certs** | ✅ Supported (requires DNS-01 challenge) |

### Staging vs Production

| Server | URL | Use Case |
|--------|-----|----------|
| **Staging** | `https://acme-staging-v02.api.letsencrypt.org/directory` | Testing (untrusted certs, no rate limits) |
| **Production** | `https://acme-v02.api.letsencrypt.org/directory` | Real usage (trusted certs, rate limited) |

### How It Works

1. **cert-manager** requests a certificate from Let's Encrypt
2. Let's Encrypt issues an **HTTP-01 challenge** (or DNS-01 for wildcards)
3. cert-manager proves domain ownership by responding to the challenge
4. Let's Encrypt issues the certificate (valid for 90 days)
5. cert-manager stores the certificate in a Kubernetes Secret
6. cert-manager **automatically renews** the certificate before expiry

---

## Why Let's Encrypt vs Other Certificate Authorities?

### Comparison with Traditional CAs (Verisign, DigiCert, GoDaddy, etc.)

| Feature | Let's Encrypt | Traditional CAs (Verisign, DigiCert, etc.) |
|---------|---------------|--------------------------------------------|
| **Cost** | ✅ **100% FREE** | ❌ **$50-$500+/year** per certificate |
| **Automation** | ✅ **Fully automated** via ACME protocol | ❌ Manual purchase, validation, and renewal |
| **Kubernetes Integration** | ✅ **Native** with cert-manager | ❌ Manual certificate management or plugins |
| **GitOps Friendly** | ✅ **Yes** - declarative YAML config | ❌ Requires manual processes or external tools |
| **Browser Trust** | ✅ **Same trust level** - trusted by all browsers | ✅ Trusted (but no advantage over Let's Encrypt) |
| **Certificate Validity** | 90 days (auto-renewed) | 1-2 years (manual renewal) |
| **Validation Time** | **Minutes** (automated) | **Hours to days** (manual verification) |
| **Wildcard Support** | ✅ **Free** (via DNS-01 challenge) | ✅ **Paid** (typically $200+/year) |
| **Rate Limits** | 50 certs/domain/week (generous) | Usually unlimited (you pay per cert) |
| **Open Source** | ✅ Non-profit, open source | ❌ Commercial, proprietary |
| **Multi-Domain Certs** | ✅ **Free** (up to 100 domains per cert) | ✅ **Paid** (additional cost per domain) |

### Why Let's Encrypt for Kubernetes/DevOps?

1. **GitOps Native**
   - Declarative YAML configuration in Helm charts
   - No manual certificate uploads or downloads
   - Certificates managed as Kubernetes resources

2. **Zero Downtime Renewals**
   - cert-manager automatically renews certificates before expiry
   - No manual intervention required
   - Certificates are refreshed seamlessly

3. **Cost Efficiency**
   - **$0 per certificate** (vs $50-$500/year per cert)
   - Perfect for microservices with many domains
   - No vendor lock-in or annual contracts

4. **Automation First**
   - ACME protocol designed for automation
   - Perfect fit for CI/CD pipelines
   - No human-in-the-loop for certificate lifecycle

5. **Same Security & Trust**
   - **Equally trusted** by all browsers as paid CAs
   - Same encryption strength (2048-bit RSA or ECC)
   - No security trade-offs

6. **Developer Experience**
   - Quick setup (minutes vs days)
   - Self-service certificates
   - No procurement or approval processes

### When to Use Traditional CAs Instead

Traditional CAs may be appropriate if you need:

- **Extended Validation (EV) certificates** - Organization name in browser address bar
- **Multi-year certificates** - Less frequent renewals (though auto-renewal makes this less important)
- **Specialized certificates** - Code signing, email signing, client certificates
- **Compliance requirements** - Some regulations may require specific CA vendors
- **Warranty/Insurance** - Some CAs offer financial guarantees (often not needed)

### Real-World Example

**Scenario**: You have 50 microservices, each with its own subdomain.

| Approach | Cost | Setup Time | Maintenance |
|----------|------|------------|-------------|
| **Let's Encrypt** | **$0** | 1 hour (automated) | None (auto-renewal) |
| **Traditional CA** | **$2,500+/year** | 1-2 weeks (manual) | Manual renewal each year |

**Bottom Line**: For 99% of Kubernetes deployments, Let's Encrypt is the optimal choice due to cost, automation, and GitOps integration.

---

## Helm Chart Integration

TLS/HTTPS is now integrated into the Helm charts:

### App Chart (`dm-nkp-gitops-custom-app`)

Creates:

- **ClusterIssuer** for Let's Encrypt (cluster-wide, created once)
- **Certificate** for app hostnames

### Observability Chart (`observability-stack`) - Local Testing Only

Creates:

- **Certificate** for observability hostname
- **Gateway** with HTTP + HTTPS listeners (for local testing)

### Quick Start with Helm

```bash
# Deploy app chart with TLS enabled (default)
helm install dm-app ./chart/dm-nkp-gitops-custom-app \
  --namespace dm-nkp-gitops-custom-app \
  --create-namespace \
  --set tls.clusterIssuer.email=your-email@example.com

# For local testing with observability stack
helm install obs-stack ./chart/observability-stack \
  --namespace observability \
  --create-namespace \
  --set gateway.enabled=true \
  --set tls.enabled=true
```

### Helm Values Configuration

```yaml
# dm-nkp-gitops-custom-app/values.yaml
tls:
  enabled: true
  clusterIssuer:
    create: true                    # Create ClusterIssuer (set false if exists)
    name: "letsencrypt-prod"
    email: "your-email@example.com" # Required for expiry notifications
    server: "https://acme-v02.api.letsencrypt.org/directory"
  certificate:
    create: true
    secretName: "dm-nkp-gitops-custom-app-tls"
    dnsNames:
      - "dm-nkp-gitops-custom-app.local"
```

---

## Manual Setup (Alternative)

Run the automated setup script:

```bash
# For staging (testing)
./scripts/setup-letsencrypt.sh your-email@example.com staging

# For production
./scripts/setup-letsencrypt.sh your-email@example.com prod
```

## Files Reference

| File | Description |
|------|-------------|
| `chart/dm-nkp-gitops-custom-app/templates/cluster-issuer.yaml` | ClusterIssuer template |
| `chart/dm-nkp-gitops-custom-app/templates/certificate.yaml` | App Certificate template |
| `chart/observability-stack/templates/certificate.yaml` | Observability Certificate template |
| `chart/observability-stack/templates/gateway.yaml` | Gateway with HTTPS (local testing) |
| `manifests/cert-manager/cluster-issuer.yaml` | Manual ClusterIssuer manifest |
| `manifests/cert-manager/gateway-certificate.yaml` | Manual Certificate manifest |
| `manifests/gateway-api/gateway.yaml` | Manual Gateway manifest |
| `scripts/setup-letsencrypt.sh` | Automated setup script |

---

## Architecture

### NKP Production Deployment

```
┌─────────────────────────────────────────────────────────────────┐
│                     NKP Platform (Pre-deployed)                  │
├─────────────────────────────────────────────────────────────────┤
│  cert-manager  │  Traefik (Gateway)  │  MetalLB  │  Gateway CRDs │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              App Chart (dm-nkp-gitops-custom-app)               │
├─────────────────────────────────────────────────────────────────┤
│  ClusterIssuer (Let's Encrypt)  │  Certificate  │  HTTPRoute    │
└─────────────────────────────────────────────────────────────────┘
```

### Local Testing Deployment

```
┌─────────────────────────────────────────────────────────────────┐
│                    Local Cluster (kind/minikube)                 │
├─────────────────────────────────────────────────────────────────┤
│  cert-manager (install manually)  │  MetalLB (install manually)  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Observability Stack Chart                    │
├─────────────────────────────────────────────────────────────────┤
│  Gateway (HTTP+HTTPS)  │  Certificate  │  HTTPRoute              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              App Chart (dm-nkp-gitops-custom-app)               │
├─────────────────────────────────────────────────────────────────┤
│  ClusterIssuer (Let's Encrypt)  │  Certificate  │  HTTPRoute    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Manual Setup Details

To manually enable HTTPS with Let's Encrypt for your Gateway API setup, follow this approach:

### Option 1: Gateway TLS Termination (Recommended)

This is the **recommended approach** for Gateway API. TLS is terminated at the Gateway, and cert-manager manages certificates automatically.

#### Step 1: Install cert-manager

```bash
# Add cert-manager Helm repo
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --wait --timeout=5m
```

#### Step 2: Create Let's Encrypt Issuer

Create `manifests/cert-manager/letsencrypt-issuer.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com  # Replace with your email
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    # HTTP-01 Challenge (recommended for production)
    - http01:
        ingress:
          class: traefik
    # Alternative: DNS-01 Challenge (for wildcards or if HTTP-01 doesn't work)
    # - dns01:
    #     cloudflare:
    #       email: your-email@example.com
    #       apiKeySecretRef:
    #         name: cloudflare-api-key
    #         key: api-key
---
# Staging issuer for testing
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: your-email@example.com  # Replace with your email
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: traefik
```

Apply it:

```bash
kubectl apply -f manifests/cert-manager/letsencrypt-issuer.yaml
```

#### Step 3: Update Gateway Configuration

Update your Gateway to include an HTTPS listener. Modify `scripts/e2e-demo-otel.sh` or create a separate Gateway manifest:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: traefik
  namespace: traefik-system
spec:
  gatewayClassName: traefik
  listeners:
    - name: web
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
    # Add HTTPS listener
    - name: websecure
      protocol: HTTPS
      port: 443
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate  # TLS termination at Gateway
        certificateRefs:
          - name: traefik-tls-cert
            kind: Secret  # cert-manager will create this secret
```

**Note**: For cert-manager to automatically manage Gateway certificates, you may need to use Traefik's cert-manager integration or create Certificates manually. See Step 4.

#### Step 4: Create Certificate Resource

Create a Certificate for your domain(s). Create `manifests/cert-manager/gateway-certificate.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: traefik-tls-cert
  namespace: traefik-system
spec:
  secretName: traefik-tls-cert  # Must match certificateRef in Gateway
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: dm-nkp-gitops-custom-app.local  # Your primary domain
  dnsNames:
    - dm-nkp-gitops-custom-app.local
    - observability.local  # Add other domains as needed
```

For multiple services/domains, create separate Certificates or use wildcards with DNS-01 challenge.

#### Step 5: Update HTTPRoute (Optional)

HTTPRoutes don't need TLS configuration when using Gateway TLS termination. However, if you want to redirect HTTP to HTTPS, you can:

1. **Option A**: Configure redirect at Gateway level (if Traefik Gateway supports it)
2. **Option B**: Use a separate HTTPRoute with redirect rules

#### Step 6: Update Traefik Service (MetalLB)

Ensure your Traefik service exposes port 443:

```bash
# Check current service
kubectl get svc traefik -n traefik-system -o yaml

# If LoadBalancer, ensure port 443 is configured
kubectl patch svc traefik -n traefik-system --type='json' \
  -p='[{"op": "add", "path": "/spec/ports/-", "value": {"port": 443, "protocol": "TCP", "name": "https"}}]'
```

Or when installing/upgrading Traefik:

```bash
helm upgrade traefik traefik/traefik \
  --namespace traefik-system \
  --set service.type=LoadBalancer \
  --set ports.websecure.exposedPort=443 \
  --reuse-values
```

### Option 2: Traefik IngressRoute with cert-manager

If you prefer using Traefik IngressRoute instead of Gateway API:

Your existing `manifests/traefik/ingressroute.yaml` already references TLS. Update it to use cert-manager annotations:

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: dm-nkp-gitops-custom-app
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`dm-nkp-gitops-custom-app.local`)
      kind: Rule
      services:
        - name: dm-nkp-gitops-custom-app
          port: 8080
  tls:
    certResolver: letsencrypt-prod  # Traefik's cert-manager integration
    # OR use cert-manager Certificate:
    # secretName: dm-nkp-gitops-custom-app-tls
```

And configure Traefik to use cert-manager:

```yaml
# Add to Traefik Helm values
certificatesResolvers:
  letsencrypt-prod:
    certManager:
      clusterIssuer: letsencrypt-prod
```

### Verification Steps

1. **Check cert-manager installation:**

   ```bash
   kubectl get pods -n cert-manager
   kubectl get clusterissuers
   ```

2. **Check Certificate status:**

   ```bash
   kubectl get certificates -A
   kubectl describe certificate traefik-tls-cert -n traefik-system
   ```

3. **Check Gateway HTTPS listener:**

   ```bash
   kubectl get gateway traefik -n traefik-system -o yaml
   # Verify websecure listener on port 443
   ```

4. **Check LoadBalancer IP:**

   ```bash
   kubectl get svc traefik -n traefik-system
   # Verify port 443 is exposed
   ```

5. **Test HTTPS access:**

   ```bash
   LB_IP=$(kubectl get svc traefik -n traefik-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   curl -k https://$LB_IP -H "Host: dm-nkp-gitops-custom-app.local"
   ```

### Troubleshooting

1. **Certificate not issuing:**
   - Check cert-manager logs: `kubectl logs -n cert-manager -l app=cert-manager`
   - Check Certificate status: `kubectl describe certificate <cert-name>`
   - Verify DNS points to LoadBalancer IP

2. **Gateway not accepting HTTPS:**
   - Verify Gateway has `websecure` listener
   - Check Traefik Gateway controller logs

3. **MetalLB not exposing port 443:**
   - Verify service has port 443 configured
   - Check MetalLB logs if IP not assigned

### Production Considerations

1. **DNS Requirements:**
   - Domains must resolve to your LoadBalancer IP
   - For HTTP-01 challenge, domain must be publicly accessible

2. **Certificate Renewal:**
   - cert-manager automatically renews certificates
   - Monitor certificate expiry: `kubectl get certificates`

3. **Staging vs Production:**
   - Use `letsencrypt-staging` for testing
   - Switch to `letsencrypt-prod` for production

4. **Multiple Domains:**
   - Create separate Certificates for each domain
   - Or use wildcard certificates with DNS-01 challenge

### Files to Create/Update

1. `manifests/cert-manager/letsencrypt-issuer.yaml` - ClusterIssuer for Let's Encrypt
2. `manifests/cert-manager/gateway-certificate.yaml` - Certificate resource
3. Update Gateway configuration to include HTTPS listener
4. Update HTTPRoute if needed (usually not required for Gateway TLS termination)
5. Update Traefik Helm values if using cert-manager resolver

### Next Steps

1. Install cert-manager
2. Create Let's Encrypt ClusterIssuer
3. Update Gateway with HTTPS listener
4. Create Certificate resources
5. Update Traefik service to expose port 443
6. Test HTTPS access

For Gateway API, Option 1 (Gateway TLS Termination) is recommended as it's the standard approach and aligns with Gateway API specifications.
