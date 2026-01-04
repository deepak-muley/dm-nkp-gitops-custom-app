# ADR-0004: Registry Path Separation for Dev and Production

## Status

Accepted

## Context

We need to separate development/PR artifacts from production artifacts in the container registry. This prevents:

- Accidental use of development artifacts in production
- Confusion about which artifacts are production-ready
- Overwriting production artifacts with development builds

## Decision

We will use separate registry paths with clear environment prefixes for easy identification:

- **Development/PR artifacts**: `ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dev/dm-nkp-gitops-custom-app`
- **Production artifacts**: `ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/prod/dm-nkp-gitops-custom-app`

The environment prefix (`/dev/` or `/prod/`) is placed early in the path structure, making it immediately obvious which environment an artifact belongs to. This improves:
- **Clarity**: Easy to identify dev vs prod at a glance
- **Organization**: Better structure in GHCR UI
- **Safety**: Reduces risk of accidentally using dev artifacts in production

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

- CI workflow pushes to `/dev/` path for PRs
- CD workflow pushes to `/prod/` path for master branch
- Makefile auto-detects branch and uses appropriate path (dev for non-master, prod for master)
- Can be overridden with `REGISTRY_ENV` variable: `make docker-push REGISTRY_ENV=dev` or `make docker-push REGISTRY_ENV=prod`

### Naming Examples

**Development (from PR or local non-master branch):**
- Docker Image: `ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dev/dm-nkp-gitops-custom-app:0.1.0-sha-abc1234`
- Helm Chart: `oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dev/dm-nkp-gitops-custom-app:0.1.0+sha-abc1234`

**Production (from master branch or tags):**
- Docker Image: `ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/prod/dm-nkp-gitops-custom-app:0.1.0-sha-abc1234`
- Helm Chart: `oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/prod/dm-nkp-gitops-custom-app:0.1.0+sha-abc1234`
