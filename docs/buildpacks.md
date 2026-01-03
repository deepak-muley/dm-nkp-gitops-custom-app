# Buildpacks Guide

This document explains how buildpacks work and how they're used in this project.

## What are Buildpacks?

Buildpacks are a Cloud Native Computing Foundation (CNCF) project that provides a higher-level abstraction for building container images. They automatically detect your application type, install dependencies, and create an optimized container image.

### Key Benefits

1. **Security**: Creates minimal, distroless images with only necessary runtime components
2. **Simplicity**: No need to write Dockerfiles - buildpacks handle the build process
3. **Consistency**: Same build process across different environments
4. **Optimization**: Automatic caching and layer optimization
5. **Best Practices**: Built-in security and performance optimizations

## How Buildpacks Work

### Buildpack Lifecycle

```
┌─────────────────────────────────────────────────────────┐
│                    Buildpack Lifecycle                    │
└─────────────────────────────────────────────────────────┘

1. DETECT Phase
   ├─ Analyzes source code
   ├─ Identifies application type (Go, Node.js, Python, etc.)
   └─ Selects appropriate buildpacks

2. ANALYZE Phase
   ├─ Reads previous image metadata
   ├─ Restores cached layers
   └─ Determines what needs to be rebuilt

3. BUILD Phase
   ├─ Downloads dependencies
   ├─ Compiles application
   ├─ Installs runtime
   └─ Configures application

4. EXPORT Phase
   ├─ Creates final image layers
   ├─ Sets image metadata
   └─ Exports to registry or local Docker
```

### Components

1. **Builder**: Contains buildpacks and a base image
   - Example: `gcr.io/buildpacks/builder:google-22`
   - Includes: Go buildpack, system libraries, runtime

2. **Buildpacks**: Collections of build logic
   - Go buildpack: Detects Go apps, builds binaries
   - System buildpack: Installs system dependencies

3. **Stack**: Base operating system image
   - Distroless: Minimal, secure base image
   - Ubuntu: Full-featured base image

## Buildpacks in This Project

### Configuration

The project uses `project.toml` to configure buildpacks:

```toml
[project]
id = "dm-nkp-gitops-custom-app"

[build]
  [[build.env]]
    name = "GOOGLE_RUNTIME_VERSION"
    value = "1.25"

  [[build.env]]
    name = "GOOGLE_BUILDABLE"
    value = "./cmd/app"

  [[build.env]]
    name = "PORT"
    value = "8080"

  [[build.env]]
    name = "METRICS_PORT"
    value = "9090"
```

### Build Process

When you run `make docker-build` or `pack build`, the following happens:

1. **Detection**: Buildpack detects Go application

   ```bash
   # Buildpack checks for:
   - go.mod file
   - Go source files
   - Build configuration
   ```

2. **Build**: Compiles the Go application

   ```bash
   # Buildpack runs:
   - go mod download
   - go build -o /layers/.../bin/app ./cmd/app
   ```

3. **Export**: Creates distroless image

   ```bash
   # Final image contains:
   - Distroless base (gcr.io/distroless/static:nonroot)
   - Compiled binary
   - Runtime configuration
   ```

### Google Buildpacks

This project uses Google's buildpacks (`gcr.io/buildpacks/builder:google-22`):

**Features:**

- Optimized for Google Cloud Platform
- Supports multiple languages (Go, Node.js, Python, Java, etc.)
- Automatic security updates
- Distroless base images

**Go Buildpack Capabilities:**

- Automatic Go version detection
- Dependency caching
- Multi-stage builds
- Security hardening

## Using Buildpacks

### Basic Usage

```bash
# Build with buildpacks
pack build my-app:latest \
  --builder gcr.io/buildpacks/builder:google-22 \
  --env GOOGLE_RUNTIME_VERSION=1.25 \
  --env GOOGLE_BUILDABLE=./cmd/app
```

### With Makefile

```bash
# Using the Makefile target
make docker-build

# This runs:
pack build ghcr.io/.../dm-nkp-gitops-custom-app:0.1.0 \
  --builder gcr.io/buildpacks/builder:google-22 \
  --env GOOGLE_RUNTIME_VERSION=1.25 \
  --env GOOGLE_BUILDABLE=./cmd/app \
  --env PORT=8080 \
  --env METRICS_PORT=9090
```

### Advanced Options

```bash
# Build with custom builder
pack build my-app \
  --builder paketobuildpacks/builder:base

# Build with verbose output
pack build my-app -v

# Build without cache
pack build my-app --clear-cache

# Build and publish directly
pack build my-app --publish
```

## Buildpack vs Dockerfile

### Dockerfile Approach

```dockerfile
FROM golang:1.25-alpine AS builder
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o app ./cmd/app

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /build/app /app
ENTRYPOINT ["/app"]
```

**Pros:**

- Full control over build process
- Explicit dependencies
- Customizable

**Cons:**

- More code to maintain
- Security updates require manual intervention
- Larger images if not optimized

### Buildpacks Approach

```bash
pack build app --builder gcr.io/buildpacks/builder:google-22
```

**Pros:**

- Automatic optimization
- Security updates handled by buildpack maintainers
- Smaller images
- Best practices built-in
- Less code to maintain

**Cons:**

- Less control over build process
- Requires understanding of buildpack configuration

## Buildpack Configuration

### Environment Variables

Buildpacks use environment variables for configuration:

| Variable | Description | Example |
|----------|-------------|---------|
| `GOOGLE_RUNTIME_VERSION` | Go version to use | `1.25` |
| `GOOGLE_BUILDABLE` | Path to build | `./cmd/app` |
| `PORT` | Application port | `8080` |
| `METRICS_PORT` | Metrics port | `9090` |

### Buildpack Detection

Buildpacks automatically detect your application:

```bash
# Go detection checks for:
- go.mod file
- *.go files
- Build configuration
```

### Custom Buildpacks

You can use custom buildpacks:

```bash
# Add custom buildpack
pack build my-app \
  --builder my-custom-builder \
  --buildpack my-buildpack
```

## Image Structure

### Buildpacks Image Layers

```
┌─────────────────────────────────────┐
│     Application Layer               │
│     - Compiled binary               │
│     - Runtime config                │
├─────────────────────────────────────┤
│     Runtime Layer                   │
│     - Go runtime (if needed)        │
│     - System libraries              │
├─────────────────────────────────────┤
│     Base Layer (Distroless)         │
│     - Minimal OS                    │
│     - Security hardened             │
└─────────────────────────────────────┘
```

### Distroless Base

Buildpacks use distroless images by default:

- **No shell**: Reduces attack surface
- **No package manager**: Prevents unauthorized installations
- **Minimal base**: Only essential runtime components
- **Non-root user**: Runs as unprivileged user

## Caching

Buildpacks use intelligent caching:

```bash
# First build (slower)
pack build my-app
# Downloads dependencies, compiles

# Subsequent builds (faster)
pack build my-app
# Reuses cached layers
```

### Cache Locations

- **Local cache**: `~/.pack/cache`
- **Registry cache**: Stored in image registry
- **Layer cache**: Individual layers cached separately

## Troubleshooting

### Build Fails

```bash
# Check buildpack logs
pack build my-app -v

# Clear cache and rebuild
pack build my-app --clear-cache

# Check builder compatibility
pack builder suggest
```

### Wrong Go Version

```bash
# Specify Go version explicitly
pack build my-app \
  --env GOOGLE_RUNTIME_VERSION=1.25
```

### Build Timeout

```bash
# Increase timeout
pack build my-app --network host
```

## Best Practices

1. **Use project.toml**: Centralize build configuration
2. **Pin builder version**: Use specific builder tags
3. **Set environment variables**: Configure via project.toml
4. **Test locally**: Build and test before pushing
5. **Monitor image size**: Buildpacks should produce smaller images
6. **Security scanning**: Scan buildpacks images regularly

## CI/CD Integration

### GitHub Actions

```yaml
- name: Build with buildpacks
  run: |
    pack build $IMAGE \
      --builder gcr.io/buildpacks/builder:google-22 \
      --env GOOGLE_RUNTIME_VERSION=1.25 \
      --publish
```

### Local CI Simulation

```bash
# Simulate CI build
make docker-build
```

## Resources

- [Buildpacks Documentation](https://buildpacks.io/docs/)
- [Google Buildpacks](https://github.com/GoogleCloudPlatform/buildpacks)
- [Pack CLI Documentation](https://buildpacks.io/docs/tools/pack/)
- [CNCF Buildpacks](https://www.cncf.io/projects/buildpacks/)

## Comparison: Buildpacks vs Dockerfile

| Feature | Buildpacks | Dockerfile |
|---------|------------|------------|
| **Ease of Use** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Security** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Image Size** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Customization** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Maintenance** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Learning Curve** | ⭐⭐⭐⭐ | ⭐⭐⭐ |

## Conclusion

Buildpacks provide a modern, secure, and efficient way to build container images. For this project, buildpacks are the recommended approach as they:

- Produce smaller, more secure images
- Automatically apply best practices
- Reduce maintenance burden
- Provide consistent builds across environments

The project includes both buildpacks (recommended) and Dockerfile (alternative) approaches, giving you flexibility while defaulting to the best practice.
