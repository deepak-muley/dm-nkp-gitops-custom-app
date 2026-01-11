# Pack Build Performance Optimization

## Why Pack Build Can Be Slow

`pack build` uses Cloud Native Buildpacks which perform several operations that can make it slower than Dockerfile-based builds:

### Main Bottlenecks

1. **Large Builder Image** (~1-2GB)
   - The `gcr.io/buildpacks/builder:google-22` builder image is large
   - First build must download and extract it
   - Subsequent builds reuse cached builder (much faster)

2. **Buildpack Lifecycle Phases**
   - **DETECT**: Analyzes source code to identify application type
   - **ANALYZE**: Reads previous build metadata, restores cache
   - **BUILD**: Downloads dependencies, compiles application
   - **EXPORT**: Creates final image layers
   - Each phase adds overhead compared to direct Docker builds

3. **Go Module Downloads**
   - Buildpacks download dependencies from scratch on each build
   - No reuse of local Go module cache by default
   - Network latency can slow down dependency downloads

4. **Layer Analysis**
   - Buildpacks analyze layers for optimization
   - Cache restoration takes time
   - Image layer creation is more complex

### Typical Build Times

- **First build (cold cache)**: 2-5 minutes
  - Downloads builder image: 1-2 minutes
  - Downloads Go modules: 30-60 seconds
  - Compiles application: 30-60 seconds
  - Creates image: 30-60 seconds

- **Subsequent builds (warm cache)**: 30-60 seconds
  - Reuses builder image: 0 seconds
  - Reuses cached Go modules: 0-10 seconds
  - Compiles only changed code: 10-30 seconds
  - Creates image: 20-30 seconds

## Optimizations Applied

### 1. Cache Image for Persistent Caching

```bash
pack build <image> --cache-image <image>:cache
```

- Stores build cache in a separate image
- Persists between builds
- Speeds up subsequent builds significantly

### 2. Pull Policy Optimization

```bash
pack build <image> --pull-policy if-not-present
```

- Only pulls builder if not already present
- Avoids unnecessary network requests
- Faster on subsequent builds

### 3. Go Module Cache Volume Mount (Optional)

```bash
pack build <image> \
  --volume "$(go env GOMODCACHE):/go/pkg/mod:ro"
```

- Reuses local Go module cache
- Avoids re-downloading dependencies
- Requires Go to be installed locally

### 4. Builder Pre-Pull

```bash
pack builder pull gcr.io/buildpacks/builder:google-22
```

- Pre-downloads builder image
- First build is faster
- Useful for CI/CD pipelines

## Faster Alternatives for Local Development

### Option 1: Use Dockerfile Build (Recommended for Local)

The project includes a Dockerfile that is **much faster** for local development:

```bash
# Fast build (~30 seconds)
docker build -t my-app:latest .

# Even faster with BuildKit cache
DOCKER_BUILDKIT=1 docker build -t my-app:latest .
```

**Benefits:**
- No builder image download
- Direct compilation
- Reuses Docker layer cache
- Faster iteration cycle

### Option 2: Use Pack with Fast Builder

Use a smaller, lighter builder for faster builds:

```bash
# Paketo tiny builder (smaller, faster)
pack build my-app \
  --builder paketobuildpacks/builder:base \
  --builder paketobuildpacks/builder:tiny
```

**Trade-offs:**
- Smaller builder = faster downloads
- Less features = may need customizations
- Still slower than Dockerfile for simple apps

### Option 3: Use BuildKit with Dockerfile

Docker BuildKit provides excellent caching:

```bash
# Enable BuildKit
export DOCKER_BUILDKIT=1

# Build with cache mount (Go modules)
docker build \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  --cache-from my-app:latest \
  -t my-app:latest .
```

## Recommendations

### For Local Development

**Use Dockerfile build** - It's 3-5x faster:

```bash
# In e2e-demo-otel.sh, this is now the default
docker build -t $IMAGE_NAME .
```

### For CI/CD and Production

**Use Pack build** - Better for production:

```bash
# In Makefile, optimized with caching
make docker-build
```

Benefits:
- Distroless base images (more secure)
- Automatic security updates
- Consistent builds across environments
- Production-ready images

### When to Use Each

| Scenario | Recommended | Reason |
|----------|------------|--------|
| Local development | `docker build` | Fast iteration, immediate feedback |
| E2E testing | `docker build` | Speed matters for frequent tests |
| CI/CD pipeline | `pack build` | Consistent, secure, production-ready |
| Production releases | `pack build` | Security and best practices |

## Performance Tips

### 1. Pre-pull Builder Image

```bash
# Before first build, pull builder once
pack builder pull gcr.io/buildpacks/builder:google-22

# Or use in CI/CD setup step
pack builder pull gcr.io/buildpacks/builder:google-22 --no-color
```

### 2. Use Build Cache

```bash
# Always use cache image for persistence
pack build my-app --cache-image my-app:cache
```

### 3. Parallel Dependency Downloads

Some buildpacks support parallel downloads. Check buildpack documentation for `BP_GO_BUILD_FLAGS` optimizations.

### 4. Network Optimization

- Use faster DNS (e.g., 8.8.8.8)
- Use mirror for Go modules (set `GOPROXY`)
- Use local proxy if in restricted network

### 5. Skip Unnecessary Phases

For development, you might skip some buildpack phases, but this requires custom buildpacks and is not recommended.

## Troubleshooting Slow Builds

### Check What's Taking Time

```bash
# Verbose output shows each phase
pack build my-app -v

# Check builder size
docker images gcr.io/buildpacks/builder:google-22

# Check cache
pack cache report
```

### Clear Cache if Needed

```bash
# Clear pack cache (forces rebuild)
pack build my-app --clear-cache

# Clear Docker cache
docker builder prune
```

### Verify Network Speed

```bash
# Test Go module download speed
time go mod download

# Test builder pull speed
time pack builder pull gcr.io/buildpacks/builder:google-22
```

## Summary

**Pack build is slower because:**
- Downloads large builder image (first time)
- Performs multiple lifecycle phases
- More complex layer management
- Better for production (security, consistency)

**Optimizations:**
- ✅ Cache image persistence
- ✅ Pull policy optimization
- ✅ Go module cache volume (optional)
- ✅ Builder pre-pull for CI/CD

**For faster local builds:**
- ✅ Use `docker build` (now default in e2e-demo-otel.sh)
- ✅ Use Dockerfile (included in project)
- ✅ Much faster iteration cycle

**Best practice:**
- Local development: Use `docker build` for speed
- Production builds: Use `pack build` for security and consistency