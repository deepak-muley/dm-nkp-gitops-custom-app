# CI/CD Pipeline Documentation

This document describes the complete CI/CD pipeline for `dm-nkp-gitops-custom-app`, including local development workflow, PR testing, and production deployment.

> **Note:** This repository includes additional workflows for security scanning, release automation, and maintenance. See [GitHub Actions Reference](./github-actions-reference.md) for complete workflow documentation.

## Overview

The CI/CD pipeline ensures that:
- All code changes are tested before merging
- Docker images and Helm charts are built and validated
- E2E tests run against built artifacts
- Production artifacts are signed and pushed to GHCR
- Code coverage is tracked and visible in PRs

## Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Local Development                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Build Helm   │  │ Build Docker │  │ Run E2E      │         │
│  │ Chart        │→ │ Image        │→ │ Tests        │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Create PR (dev → master)                     │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │                    CI Workflow                            │ │
│  │  ┌────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │ │
│  │  │ Test   │→ │ Build    │→ │ Docker   │→ │ Helm     │  │ │
│  │  │        │  │          │  │ Build   │  │ Package  │  │ │
│  │  └────────┘  └──────────┘  └──────────┘  └──────────┘  │ │
│  │       │            │             │              │        │ │
│  │       └────────────┴─────────────┴──────────────┘        │ │
│  │                            │                              │ │
│  │                            ▼                              │ │
│  │                    ┌──────────────┐                       │ │
│  │                    │ E2E Tests    │                       │ │
│  │                    │ (with built │                       │ │
│  │                    │  artifacts)  │                       │ │
│  │                    └──────────────┘                       │ │
│  │                            │                              │ │
│  │                            ▼                              │ │
│  │                    ┌──────────────┐                       │ │
│  │                    │ Codecov      │                       │ │
│  │                    │ (PR comment) │                       │ │
│  │                    └──────────────┘                       │ │
│  └──────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼ (Merge to master)
┌─────────────────────────────────────────────────────────────────┐
│                    CD Workflow (master branch)                   │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │ │
│  │  │ Build & Push │→ │ Sign Image   │→ │ Push Helm   │  │ │
│  │  │ Docker Image │  │ (cosign)     │  │ Chart       │  │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │ │
│  │       │                                                    │ │
│  │       ▼                                                    │ │
│  │  ┌──────────────┐                                         │ │
│  │  │ E2E Tests    │                                         │ │
│  │  │ (with prod   │                                         │ │
│  │  │  artifacts)  │                                         │ │
│  │  └──────────────┘                                         │ │
│  └──────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Local Development Workflow

### Step 1: Build Locally

Before pushing changes, developers should build and test locally:

```bash
# Build Helm chart
make helm-chart

# Build Docker image
make docker-build

# Run all tests including e2e
make test
make e2e-tests
```

### Step 2: Create PR

Once local tests pass, create a PR from `dev` branch to `master`:

```bash
git checkout -b feature/my-feature
# ... make changes ...
git commit -m "feat: add new feature"
git push origin feature/my-feature
# Create PR via GitHub UI or CLI
```

## CI Workflow (Pull Requests)

**Trigger:** All pull requests (any target branch)

**Location:** `.github/workflows/ci.yml`

### Jobs

#### 1. `test` Job
- **Purpose:** Run unit tests, integration tests, linting, and security checks
- **Steps:**
  - Set up Go environment
  - Download dependencies
  - Check for secrets (prevent accidental commits)
  - Run linters
  - Run unit tests
  - Run integration tests
  - Upload coverage to Codecov

**Codecov Integration:**
- Coverage reports are uploaded to Codecov
- Codecov bot comments on PRs with coverage changes
- Coverage badge appears in PR status checks

#### 2. `docker-build` Job
- **Purpose:** Build Docker image to verify it builds correctly
- **Dependencies:** `test` job must pass
- **Steps:**
  - Set up Docker Buildx
  - Build Docker image using Cloud Native Buildpacks
  - Verify image builds successfully
  - **Note:** Image is NOT pushed to registry (test only)

#### 3. `helm` Job
- **Purpose:** Package and validate Helm chart
- **Dependencies:** `test` job must pass
- **Steps:**
  - Install Helm
  - Package Helm chart
  - Lint Helm chart
  - Validate Helm templates
  - Upload chart as artifact for e2e tests

#### 4. `build` Job
- **Purpose:** Build Go binary
- **Dependencies:** `test` job must pass
- **Steps:**
  - Build application binary
  - Upload binary as artifact

#### 5. `e2e` Job
- **Purpose:** Run end-to-end tests using built Docker image and Helm chart
- **Dependencies:** `docker-build` and `helm` jobs must pass
- **Steps:**
  - Set up Kubernetes environment (kind)
  - Install kubectl and Helm
  - Download Helm chart artifact from `helm` job
  - Build Docker image (same as `docker-build` job)
  - Run e2e tests against built artifacts
  - Tests deploy application to Kubernetes using Helm chart
  - Tests verify application functionality

**E2E Test Coverage:**
- Application deployment to Kubernetes
- Health check endpoints
- Metrics endpoint
- Service discovery
- Monitoring integration (Prometheus/Grafana)

#### 6. `kubesec` Job
- **Purpose:** Security scanning of Kubernetes manifests
- **Dependencies:** `test` job must pass
- **Steps:**
  - Install kubesec
  - Scan base Kubernetes manifests
  - Scan Helm chart templates

### Artifacts

- **Helm Chart:** Uploaded by `helm` job, downloaded by `e2e` job
- **Binary:** Uploaded by `build` job (for reference)

### Status Checks

All jobs must pass before PR can be merged:
- ✅ `test` - Unit/integration tests pass
- ✅ `docker-build` - Docker image builds
- ✅ `helm` - Helm chart packages and validates
- ✅ `e2e` - E2E tests pass with built artifacts
- ✅ `kubesec` - Security scans pass
- ✅ `codecov/patch` - Coverage check (if configured)

## CD Workflow (Master Branch)

**Trigger:** Pushes to `master` branch or tags starting with `v*`

**Location:** `.github/workflows/cd.yml`

### Jobs

#### 1. `build-and-push` Job
- **Purpose:** Build, sign, and push production artifacts to GHCR
- **Steps:**
  - Set up Docker Buildx
  - Log in to GitHub Container Registry
  - Extract version (with Git SHA for immutable versioning)
  - Build Docker image using Cloud Native Buildpacks
  - Push Docker image to GHCR
  - Sign Docker image with cosign (keyless signing)
  - Package Helm chart
  - Push Helm chart to GHCR

**Versioning:**
- Docker images: `0.1.0-sha-abc1234` (uses `-` because Docker tags don't allow `+`)
- Helm charts: `0.1.0+sha-abc1234` (uses `+` per SemVer build metadata)

**Image Signing:**
- Images are signed using cosign keyless signing
- Signatures provide authenticity and integrity verification
- See [Image Signing Documentation](./image-signing.md) for details

#### 2. `e2e` Job
- **Purpose:** Run e2e tests against production artifacts from GHCR
- **Dependencies:** `build-and-push` job must complete
- **Steps:**
  - Set up Kubernetes environment (kind)
  - Log in to GHCR
  - Pull Docker image from GHCR (the one just pushed)
  - Pull Helm chart from GHCR (the one just pushed)
  - Run e2e tests against production artifacts
  - Verify production artifacts work correctly in Kubernetes

**Why E2E After Push?**
- Validates that artifacts pushed to GHCR are functional
- Ensures production-ready artifacts work in real environment
- Catches any issues with artifact publishing

## Code Coverage

### Codecov Integration

**Configuration:**
- Coverage reports are uploaded in the `test` job
- Codecov token stored in `secrets.CODECOV_TOKEN`
- Coverage file: `coverage/unit-coverage.out`

**PR Integration:**
- Codecov bot automatically comments on PRs
- Shows coverage changes (increase/decrease)
- Displays coverage percentage
- Highlights uncovered lines

**Viewing Coverage:**
1. Check PR comments for Codecov report
2. Click "Details" link in PR status checks
3. View full report on codecov.io

**Coverage Target:**
- Aim for >80% coverage for production code
- Critical paths should have 100% coverage

## Workflow Summary

### On Pull Request

| Job | Purpose | Artifacts |
|-----|---------|-----------|
| `test` | Run tests, linting, security checks | Coverage report → Codecov |
| `docker-build` | Build Docker image (test) | None (local only) |
| `helm` | Package Helm chart | Helm chart `.tgz` |
| `build` | Build binary | Binary artifact |
| `e2e` | Test with built artifacts | None |
| `kubesec` | Security scanning | None |

### On Merge to Master

| Job | Purpose | Artifacts |
|-----|---------|-----------|
| `build-and-push` | Build, sign, push to GHCR | Docker image, Helm chart in GHCR |
| `e2e` | Test production artifacts | None |

## Required Secrets

### GitHub Secrets

- `CODECOV_TOKEN` - Codecov upload token
  - Get from: https://codecov.io/gh/deepak-muley/dm-nkp-gitops-custom-app/settings
  - Required for: Coverage reporting in PRs

### GitHub Permissions

The workflows require the following permissions:
- `contents: read` - Read repository contents
- `packages: write` - Push to GHCR
- `id-token: write` - For keyless signing with cosign

## Troubleshooting

### CI Fails on PR

**Issue:** Tests fail
- **Solution:** Check test output, fix failing tests locally first

**Issue:** Docker build fails
- **Solution:** Verify Dockerfile/buildpacks configuration, test locally

**Issue:** Helm chart validation fails
- **Solution:** Run `helm lint` and `helm template` locally

**Issue:** E2E tests fail
- **Solution:** Check Kubernetes setup, verify image builds correctly

**Issue:** Codecov not showing in PR
- **Solution:** 
  - Verify `CODECOV_TOKEN` secret is set
  - Check Codecov project settings
  - Ensure coverage file is generated correctly

### CD Fails on Master

**Issue:** Image push fails
- **Solution:** Check GHCR permissions, verify `GITHUB_TOKEN` has write access

**Issue:** Image signing fails
- **Solution:** Verify `id-token: write` permission is set

**Issue:** E2E tests fail with production artifacts
- **Solution:** Check if artifacts were pushed correctly, verify image/chart versions

## Best Practices

1. **Always Test Locally First**
   - Run `make test` and `make e2e-tests` before pushing
   - Fix issues locally to avoid CI failures

2. **Keep PRs Small**
   - Smaller PRs are easier to review
   - Faster CI runs
   - Easier to debug failures

3. **Monitor Coverage**
   - Aim to maintain or increase coverage
   - Address coverage decreases in PRs

4. **Review CI Output**
   - Check all job outputs, not just failures
   - Look for warnings that might become issues

5. **Use Meaningful Commit Messages**
   - Helps with debugging CI failures
   - Better git history

## Related Documentation

- [Testing Guide](./testing.md) - Detailed testing documentation
- [Image Signing](./image-signing.md) - Container image signing
- [Helm Deployment](./helm-deployment.md) - Helm chart deployment
- [Development Guide](./development.md) - Local development setup

## Workflow Files

- **CI:** `.github/workflows/ci.yml`
- **CD:** `.github/workflows/cd.yml`

## Quick Reference

### Local Development
```bash
make helm-chart      # Build Helm chart
make docker-build    # Build Docker image
make test            # Run all tests
make e2e-tests       # Run e2e tests
```

### CI Commands (in workflows)
```bash
make deps            # Download dependencies
make check-secrets   # Check for secrets
make lint            # Run linters
make unit-tests      # Run unit tests
make integration-tests # Run integration tests
make e2e-tests       # Run e2e tests
make helm-chart      # Package Helm chart
```

### CD Commands (in workflows)
```bash
pack build           # Build Docker image
cosign sign          # Sign Docker image
helm package         # Package Helm chart
helm push            # Push Helm chart to OCI registry
```

