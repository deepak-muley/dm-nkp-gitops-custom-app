# Manifests vs Helm Charts: Understanding the Difference

This document explains the difference between the `manifests/` folder and the `chart/templates/` folder, and when to use each.

## Overview

Both folders contain Kubernetes YAML manifests, but they serve different purposes:

- **`manifests/`** - Raw, static Kubernetes YAML files
- **`chart/templates/`** - Helm chart templates with dynamic values

## Key Differences

### 1. **Static vs Dynamic**

#### `manifests/` - Static YAML
```yaml
# manifests/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dm-nkp-gitops-custom-app  # Hard-coded name
spec:
  replicas: 2  # Hard-coded value
  containers:
  - image: ghcr.io/.../dm-nkp-gitops-custom-app:0.1.0  # Hard-coded image
```

**Characteristics:**
- ✅ Simple and straightforward
- ✅ Direct `kubectl apply`
- ❌ No customization without editing files
- ❌ Hard to manage multiple environments
- ❌ Values are hard-coded

#### `chart/templates/` - Dynamic Templates
```yaml
# chart/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "dm-nkp-gitops-custom-app.fullname" . }}  # Dynamic name
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}  # From values.yaml
  {{- end }}
  containers:
  - image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"  # Dynamic image
```

**Characteristics:**
- ✅ Highly customizable via `values.yaml`
- ✅ Supports multiple environments (dev, staging, prod)
- ✅ Template functions and conditionals
- ❌ Requires Helm to render
- ❌ More complex setup

### 2. **Usage**

#### Using `manifests/`
```bash
# Direct application - no processing needed
kubectl apply -f manifests/base/

# Or with envsubst for basic templating
envsubst < manifests/gateway-api/httproute-template.yaml | kubectl apply -f -
```

#### Using `chart/templates/`
```bash
# Render templates with Helm
helm template my-release chart/dm-nkp-gitops-custom-app

# Install with custom values
helm install my-app chart/dm-nkp-gitops-custom-app -f values-dev.yaml

# Upgrade
helm upgrade my-app chart/dm-nkp-gitops-custom-app --set replicaCount=5
```

### 3. **Customization**

#### `manifests/` - Limited Customization
```bash
# Option 1: Edit files directly
vim manifests/base/deployment.yaml
kubectl apply -f manifests/base/

# Option 2: Use envsubst (basic)
export REPLICAS=3
envsubst < manifests/base/deployment.yaml | kubectl apply -f -

# Option 3: Use kustomize (advanced)
kubectl apply -k manifests/overlays/production/
```

#### `chart/templates/` - Rich Customization
```bash
# Option 1: Use values.yaml
helm install my-app chart/ -f values.yaml

# Option 2: Override specific values
helm install my-app chart/ --set replicaCount=5 --set image.tag=0.2.0

# Option 3: Multiple value files
helm install my-app chart/ -f values.yaml -f values-prod.yaml

# Option 4: Environment-specific
helm install my-app chart/ -f values-dev.yaml
helm install my-app chart/ -f values-prod.yaml
```

### 4. **File Structure**

#### `manifests/` Structure
```
manifests/
├── base/                    # Base Kubernetes resources
│   ├── deployment.yaml     # Static deployment
│   └── service.yaml        # Static service
├── traefik/                # Traefik-specific manifests
│   └── ingressroute.yaml
└── gateway-api/             # Gateway API manifests
    ├── httproute.yaml
    └── httproute-template.yaml  # Template for envsubst
```

#### `chart/templates/` Structure
```
chart/dm-nkp-gitops-custom-app/
├── Chart.yaml              # Chart metadata
├── values.yaml             # Default values
└── templates/
    ├── _helpers.tpl        # Reusable template functions
    ├── deployment.yaml     # Template with variables
    ├── service.yaml        # Template with variables
    ├── serviceaccount.yaml
    ├── servicemonitor.yaml
    └── hpa.yaml            # Conditional (only if autoscaling enabled)
```

### 5. **When to Use Each**

#### Use `manifests/` when:
- ✅ Simple deployments with fixed values
- ✅ Quick testing and development
- ✅ One-off deployments
- ✅ You prefer `kubectl` directly
- ✅ No need for multiple environments
- ✅ CI/CD uses raw YAML
- ✅ GitOps tools (ArgoCD, Flux) that work with raw YAML

#### Use `chart/templates/` when:
- ✅ Production deployments
- ✅ Multiple environments (dev, staging, prod)
- ✅ Need to customize values per environment
- ✅ Package and distribute applications
- ✅ Version management and releases
- ✅ Complex deployments with conditionals
- ✅ Reusable across projects
- ✅ Helm ecosystem integration

### 6. **Real-World Example**

#### Scenario: Deploy to 3 environments

**Using `manifests/`:**
```bash
# Create 3 separate files or use envsubst
# dev-deployment.yaml
replicas: 1
image: app:dev

# staging-deployment.yaml
replicas: 2
image: app:staging

# prod-deployment.yaml
replicas: 5
image: app:prod

# Apply each
kubectl apply -f dev-deployment.yaml
kubectl apply -f staging-deployment.yaml
kubectl apply -f prod-deployment.yaml
```

**Using `chart/templates/`:**
```bash
# One chart, multiple value files
# values-dev.yaml
replicaCount: 1
image:
  tag: dev

# values-prod.yaml
replicaCount: 5
image:
  tag: prod

# Deploy
helm install app chart/ -f values-dev.yaml
helm install app chart/ -f values-prod.yaml
```

### 7. **Template Features Comparison**

| Feature | `manifests/` | `chart/templates/` |
|---------|-------------|-------------------|
| Variables | ❌ (use envsubst) | ✅ `.Values.*` |
| Conditionals | ❌ | ✅ `{{- if }}` |
| Loops | ❌ | ✅ `{{- range }}` |
| Functions | ❌ | ✅ `{{ include }}` |
| Defaults | ❌ | ✅ `{{ .Values.x \| default "y" }}` |
| Helpers | ❌ | ✅ `_helpers.tpl` |
| Dependencies | ❌ | ✅ `Chart.yaml` dependencies |

### 8. **In This Project**

This project provides **both** approaches:

#### `manifests/` - Used for:
- **Base resources** (`manifests/base/`) - Simple, direct deployment
- **Traefik integration** (`manifests/traefik/`) - Environment-specific ingress
- **Gateway API** (`manifests/gateway-api/`) - With envsubst template support
- **E2E tests** - Quick deployment in kind clusters

**Note**: Monitoring stack (Prometheus, Grafana) is now deployed via Helm charts. See `scripts/setup-monitoring-helm.sh` or `make setup-monitoring-helm`.

#### `chart/templates/` - Used for:
- **Production deployments** - Full-featured Helm chart
- **Multiple environments** - Customize via values.yaml
- **OCI registry distribution** - Package and push to `ghcr.io`
- **Enterprise deployments** - Standard Helm workflow
- **CI/CD pipelines** - Helm-based deployments

### 9. **Rendering Comparison**

#### `manifests/` - Direct Application
```bash
# What you see is what you get
cat manifests/base/deployment.yaml
kubectl apply -f manifests/base/deployment.yaml
```

#### `chart/templates/` - Template Rendering
```bash
# See rendered output
helm template my-release chart/dm-nkp-gitops-custom-app

# Or with custom values
helm template my-release chart/dm-nkp-gitops-custom-app \
  --set replicaCount=5 \
  --set image.tag=0.2.0

# Then apply
helm install my-release chart/dm-nkp-gitops-custom-app
```

### 10. **Best Practices**

#### For `manifests/`:
- Keep them simple and readable
- Use consistent naming
- Document any required environment variables
- Use kustomize for overlays if needed
- Version control all changes

#### For `chart/templates/`:
- Use meaningful default values
- Document all configurable values
- Use `_helpers.tpl` for reusable logic
- Test with `helm template` before deploying
- Version your charts properly
- Use semantic versioning

## Summary

| Aspect | `manifests/` | `chart/templates/` |
|--------|-------------|-------------------|
| **Type** | Static YAML | Dynamic templates |
| **Tool** | kubectl | Helm |
| **Customization** | Limited | Extensive |
| **Complexity** | Simple | Moderate |
| **Use Case** | Quick deploys, testing | Production, multi-env |
| **Flexibility** | Low | High |
| **Learning Curve** | Easy | Moderate |

## Recommendation

- **Start with `manifests/`** for development and testing
- **Use `chart/templates/`** for production and when you need customization
- **Keep both** for flexibility - use manifests for quick tests, charts for production

Both approaches are valid and serve different needs. This project provides both to give you maximum flexibility!

