# ADR-0002: Use Cloud Native Buildpacks for Container Images

## Status

Accepted

## Context

We need to build container images for the application. There are several options:
- Dockerfile-based builds
- Cloud Native Buildpacks
- Multi-stage Dockerfiles
- Buildah/Podman

## Decision

We will use Cloud Native Buildpacks (CNB) with the Google builder for building container images.

## Consequences

### Positive
- **Security**: Distroless base images reduce attack surface
- **Simplicity**: No need to maintain Dockerfiles
- **Consistency**: Standardized build process
- **Best Practices**: Follows CNCF recommendations
- **Automatic Updates**: Base images updated by buildpack maintainers

### Negative
- **Less Control**: Less fine-grained control compared to Dockerfiles
- **Learning Curve**: Team needs to understand buildpacks
- **Debugging**: Slightly harder to debug build issues

### Implementation
- Use `pack` CLI for local builds
- Use Google builder (`gcr.io/buildpacks/builder:google-22`)
- Configure via `project.toml` for build-time environment variables
- Images are automatically optimized and security-hardened

