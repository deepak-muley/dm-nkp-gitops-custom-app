# Differentiating Docker Images and Helm Charts in GHCR

This document explains how to differentiate between Docker images and Helm chart artifacts in GitHub Container Registry (GHCR).

## Current Setup

Both artifacts are stored in the same registry but are different types:

### Docker Image

```
ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:<version>
```

### Helm Chart

```
oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:<version>
```

**Note:** They currently share the same package name. While this works, using different names can make it clearer.

## How to Differentiate

### 1. **By Package Type in GitHub UI**

In the GitHub Packages UI (`https://github.com/users/deepak-muley/packages`), they appear as separate packages:

- **Docker Image**: Shows as "Container" package type with Docker icon
- **Helm Chart**: Shows as "Container" package type but with different metadata

### 2. **By How They're Referenced**

**Docker Image:**

```bash
# Pull image
docker pull ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0+sha-abc1234

# Inspect image
docker inspect ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0+sha-abc1234

# List tags
crane ls ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app
```

**Helm Chart:**

```bash
# Pull chart
helm pull oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app --version 0.1.0+sha-abc1234

# Install chart
helm install my-app oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app --version 0.1.0+sha-abc1234

# Show chart info
helm show chart oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app --version 0.1.0+sha-abc1234
```

### 3. **By Media Type**

You can check the media type to differentiate:

**Docker Image:**

```bash
# Using crane
crane manifest ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0+sha-abc1234 | jq .mediaType
# Output: "application/vnd.docker.distribution.manifest.v2+json"
```

**Helm Chart:**

```bash
# Using crane
crane manifest ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0+sha-abc1234 | jq .mediaType
# Output: "application/vnd.oci.image.manifest.v1+json" (with Helm-specific annotations)
```

### 4. **By GitHub API**

**List Docker Images:**

```bash
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/user/packages?package_type=container
```

**Get Package Details:**

```bash
# For Docker image
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/users/deepak-muley/packages/container/dm-nkp-gitops-custom-app

# Note: Both may show up under the same package name if they share it
```

### 5. **By Artifact Annotations**

Helm charts have specific OCI annotations:

```bash
# Check annotations for Helm chart
crane manifest ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0+sha-abc1234 | \
  jq '.annotations | keys'

# Helm charts will have annotations like:
# - "org.opencontainers.image.title"
# - "org.opencontainers.image.description"
# - "io.artifacthub.package.readme"
```

## Recommended: Use Different Package Names

For better clarity, consider using different package names:

### Option 1: Separate by Suffix

**Docker Image:**

```
ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:<version>
```

**Helm Chart:**

```
oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app-chart:<version>
```

### Option 2: Separate by Path

**Docker Image:**

```
ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/images/dm-nkp-gitops-custom-app:<version>
```

**Helm Chart:**

```
oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/charts/dm-nkp-gitops-custom-app:<version>
```

### Option 3: Keep Current (Works Fine)

The current setup works because:

- They're accessed differently (docker vs helm commands)
- GitHub UI shows them separately based on metadata
- OCI registries support multiple artifact types per package name

## Querying and Listing

### List All Docker Images

```bash
# Using GitHub CLI
gh api user/packages?package_type=container | jq '.[] | select(.name | contains("dm-nkp-gitops-custom-app"))'

# Using crane
crane ls ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app
```

### List All Helm Charts

```bash
# Using helm
helm search repo oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app --versions

# Using crane (same as images, but check media type)
crane ls ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app
```

### Check What Type an Artifact Is

```bash
# Function to check artifact type
check_artifact_type() {
  local ref=$1
  local manifest=$(crane manifest "$ref" 2>/dev/null)
  
  if echo "$manifest" | jq -e '.annotations."org.opencontainers.image.title"' > /dev/null 2>&1; then
    echo "Helm Chart"
  elif echo "$manifest" | jq -e '.config' > /dev/null 2>&1; then
    echo "Docker Image"
  else
    echo "Unknown OCI Artifact"
  fi
}

# Usage
check_artifact_type ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0+sha-abc1234
```

## Makefile Targets

The Makefile provides targets to work with each type:

**Docker Image:**

```bash
make docker-build      # Build image
make docker-push       # Push image
make docker-sign       # Sign image
make docker-verify     # Verify signature
```

**Helm Chart:**

```bash
make helm-chart        # Package chart
make push-helm-chart   # Push chart
make helm-chart-digest # Get chart digest
```

## GitHub Packages UI

In the GitHub web interface:

1. Go to your repository
2. Click on "Packages" in the right sidebar
3. You'll see separate entries for:
   - Container images (with Docker icon)
   - Helm charts (with Helm icon, if metadata is set correctly)

## Best Practices

1. **Use Descriptive Names**: If using the same package name, ensure your CI/CD clearly labels what's being pushed

2. **Version Consistently**: Use the same versioning scheme for both (immutable versioning with Git SHA)

3. **Document Clearly**: Document which artifact is which in your README/docs

4. **Use Different Names (Optional)**: Consider using different package names for clarity:
   - `dm-nkp-gitops-custom-app` for Docker images
   - `dm-nkp-gitops-custom-app-chart` for Helm charts

5. **Tag Appropriately**: Use semantic versioning and immutable tags consistently

## Troubleshooting

### Can't Find Chart in GitHub UI

**Issue**: Chart doesn't appear separately
**Solution**: Helm charts may appear under the same package name. Check the package details and look for different media types.

### Confusion Between Image and Chart

**Issue**: Hard to tell which is which
**Solution**:

- Use different package names (recommended)
- Or check the artifact type using the methods above
- Use the appropriate tool (docker vs helm) to interact with each

### Same Version for Both

**Issue**: Both use the same version tag
**Solution**: This is fine! They're different artifacts, so the same version tag is acceptable. The immutable versioning (with Git SHA) ensures uniqueness.

## References

- [GitHub Container Registry Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Helm OCI Support](https://helm.sh/docs/topics/registries/)
- [OCI Artifacts Specification](https://github.com/opencontainers/artifacts)
