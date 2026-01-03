# ADR-0004: Registry Path Separation for Dev and Production

## Status

Accepted

## Context

We need to separate development/PR artifacts from production artifacts in the container registry. This prevents:
- Accidental use of development artifacts in production
- Confusion about which artifacts are production-ready
- Overwriting production artifacts with development builds

## Decision

We will use separate registry paths:
- **Development/PR artifacts**: `ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app/dev`
- **Production artifacts**: `ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app`

## Consequences

### Positive
- **Clear Separation**: Clear distinction between dev and production artifacts
- **Safety**: Prevents accidental production deployments from dev artifacts
- **Organization**: Better organization of artifacts in registry
- **CI/CD Clarity**: CI pushes to `/dev`, CD pushes to main path

### Negative
- **Two Paths**: Need to manage two registry paths
- **Documentation**: Need to document which path to use when
- **Makefile Logic**: Makefile needs branch detection logic

### Implementation
- CI workflow pushes to `/dev` path for PRs
- CD workflow pushes to main path for master branch
- Makefile auto-detects branch and uses appropriate path
- Can be overridden with `REGISTRY_PATH` environment variable

