# AI Agents Guide

This document provides context and guidance for AI agents interacting with this repository. It describes the repository structure, key workflows, conventions, and how AI agents can effectively work with this codebase.

## Repository Overview

**Name:** `dm-nkp-gitops-custom-app`  
**Type:** Go application with Kubernetes deployment  
**Purpose:** Reference implementation for NKP (Nutanix Kubernetes Platform) with production-ready CI/CD

## Key Characteristics

- **Language:** Go 1.25
- **Container:** Cloud Native Buildpacks (Google builder)
- **Orchestration:** Kubernetes with Helm charts
- **Registry:** GitHub Container Registry (GHCR)
- **CI/CD:** GitHub Actions
- **Security:** Image signing (cosign), vulnerability scanning (Trivy, CodeQL)
- **Testing:** Unit, integration, and e2e tests

## Repository Structure

```
.
├── .github/
│   ├── workflows/          # GitHub Actions workflows
│   │   ├── ci.yml          # Continuous Integration
│   │   ├── cd.yml          # Continuous Deployment
│   │   ├── security.yml    # Security scanning
│   │   ├── release.yml     # Release automation
│   │   ├── stale.yml       # Stale management
│   │   ├── auto-merge.yml  # Auto-merge dependencies
│   │   ├── label.yml       # Auto-labeling
│   │   └── performance.yml # Performance testing
│   ├── dependabot.yml      # Dependency updates
│   └── labeler*.yml        # Labeling rules
├── cmd/app/                 # Application entry point
├── internal/                 # Internal packages
│   ├── metrics/             # Prometheus metrics
│   └── server/              # HTTP server
├── chart/                    # Helm chart
│   └── dm-nkp-gitops-custom-app/
├── manifests/                # Kubernetes manifests
│   ├── base/                # Base manifests
│   ├── gateway-api/         # Gateway API resources
│   └── traefik/             # Traefik resources
├── scripts/                  # Utility scripts
├── tests/                    # Test files
│   ├── e2e/                 # End-to-end tests
│   └── integration/         # Integration tests
├── docs/                     # Documentation
├── Makefile                  # Build automation
├── go.mod                    # Go dependencies
└── Dockerfile                # (Not used - uses buildpacks)
```

## CI/CD Pipeline

### Workflow Overview

**CI Workflow** (`.github/workflows/ci.yml`):

- **Triggers:** All PRs, pushes to main/master/dev
- **Jobs:**
  - `test` - Unit/integration tests, linting, security checks
  - `docker-build` - Build Docker image (test only)
  - `helm` - Package and validate Helm chart
  - `build` - Build Go binary
  - `e2e` - End-to-end tests with built artifacts
  - `kubesec` - Security scanning

**CD Workflow** (`.github/workflows/cd.yml`):

- **Triggers:** Pushes to master, version tags
- **Jobs:**
  - `build-and-push` - Build, sign, push artifacts to GHCR
  - `e2e` - Test production artifacts from GHCR

### Key Patterns

1. **Immutable Versioning:**
   - Docker images: `0.1.0-sha-abc1234` (uses `-`)
   - Helm charts: `0.1.0+sha-abc1234` (uses `+`)

2. **Image Signing:**
   - All production images signed with cosign (keyless)
   - Provides authenticity and integrity

3. **E2E Testing:**
   - Tests run with built artifacts (not just code)
   - Validates complete deployment workflow

## Key Files for AI Agents

### Build & Test

- **`Makefile`** - Primary build automation
  - Key targets: `build`, `test`, `e2e-tests`, `helm-chart`, `docker-build`
  - Use `make help` to see all targets

- **`go.mod`** - Go module dependencies
  - Language: Go 1.25
  - Main module: `github.com/deepak-muley/dm-nkp-gitops-custom-app`

### Configuration

- **`chart/dm-nkp-gitops-custom-app/values.yaml`** - Helm chart defaults
- **`chart/dm-nkp-gitops-custom-app/Chart.yaml`** - Chart metadata
- **`.github/workflows/*.yml`** - CI/CD workflows

### Documentation

- **`docs/cicd-pipeline.md`** - Complete CI/CD documentation
- **`docs/github-actions-reference.md`** - All workflows documented
- **`README.md`** - Project overview

## Common Tasks for AI Agents

### 1. Understanding the Codebase

**Key Questions to Answer:**

- What does this application do?
- How is it deployed?
- What are the dependencies?
- What tests exist?

**Files to Read:**

1. `README.md` - Project overview
2. `cmd/app/main.go` - Application entry point
3. `go.mod` - Dependencies
4. `chart/dm-nkp-gitops-custom-app/values.yaml` - Deployment config

### 2. Making Code Changes

**Workflow:**

1. Create feature branch from `dev`
2. Make changes
3. Run local tests: `make test`
4. Build locally: `make build`, `make docker-build`
5. Test e2e: `make e2e-tests`
6. Create PR to `master`
7. CI runs automatically

**Important:**

- All PRs trigger CI (tests, builds, e2e)
- Codecov tracks coverage
- Security scans run automatically

### 3. Understanding CI/CD

**CI Runs On:**

- All pull requests
- Pushes to main/master/dev branches

**CD Runs On:**

- Pushes to master branch only
- Version tags (v*)

**Key Workflows:**

- `ci.yml` - Testing and validation
- `cd.yml` - Building and deploying
- `security.yml` - Security scanning
- `release.yml` - Release automation

### 4. Deployment Process

**Production Deployment:**

1. Code merged to `master`
2. CD workflow builds Docker image
3. Image signed with cosign
4. Image and Helm chart pushed to GHCR
5. E2E tests run with production artifacts

**Artifacts:**

- Docker image: `ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:<version>`
- Helm chart: `oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:<version>`

## Code Patterns and Conventions

### Go Code Structure

**Package Organization:**

- `cmd/app/` - Application entry point
- `internal/` - Internal packages (not importable)
- `tests/` - Test files

**Testing:**

- Unit tests: `*_test.go` files alongside code
- Integration tests: `tests/integration/` with `//go:build integration`
- E2E tests: `tests/e2e/` with `//go:build e2e`

**Test Framework:**

- Ginkgo (BDD-style)
- Gomega (matchers)

### Kubernetes Patterns

**Manifests:**

- Base manifests: `manifests/base/`
- Helm chart: `chart/dm-nkp-gitops-custom-app/`
- Gateway API: `manifests/gateway-api/`
- Traefik: `manifests/traefik/`

**Security:**

- Non-root user (65532)
- Read-only root filesystem
- Dropped capabilities
- Security contexts configured

### Makefile Conventions

**Common Targets:**

- `make help` - Show all targets
- `make build` - Build binary
- `make test` - Run all tests
- `make e2e-tests` - Run e2e tests
- `make docker-build` - Build Docker image
- `make helm-chart` - Package Helm chart

**Pattern:**

- Targets use `##` for help text
- Dependencies are explicit
- Targets are idempotent

## AI Agent Interaction Patterns

### 1. Code Analysis

**When analyzing code:**

- Check `go.mod` for dependencies
- Review `internal/` packages for structure
- Check `tests/` for test coverage
- Review `Makefile` for build process

**Key Questions:**

- What does this function/package do?
- Are there tests for this?
- How is this deployed?

### 2. Making Changes

**Before making changes:**

1. Understand the current implementation
2. Check existing tests
3. Review related documentation
4. Understand deployment impact

**When making changes:**

1. Follow existing patterns
2. Add/update tests
3. Update documentation if needed
4. Ensure CI will pass

**After making changes:**

1. Run local tests
2. Verify builds work
3. Check for linting errors
4. Ensure security scans pass

### 3. Understanding Workflows

**CI Workflow Analysis:**

- Check `.github/workflows/ci.yml`
- Understand job dependencies
- Know what runs on PRs vs pushes

**CD Workflow Analysis:**

- Check `.github/workflows/cd.yml`
- Understand deployment process
- Know artifact locations

### 4. Debugging Issues

**Common Issues:**

- CI failures: Check workflow logs
- Test failures: Run locally first
- Build failures: Check dependencies
- Security issues: Review security scans

**Debugging Steps:**

1. Reproduce locally
2. Check logs/errors
3. Review related code
4. Check documentation
5. Verify configuration

## Important Context for AI Agents

### Versioning

**Immutable Versioning:**

- Every build gets unique version with Git SHA
- Prevents overwrites
- Enables traceability

**Format:**

- Images: `0.1.0-sha-abc1234`
- Charts: `0.1.0+sha-abc1234`

### Security

**Security Measures:**

- Image signing (cosign)
- Vulnerability scanning (Trivy)
- Code analysis (CodeQL)
- Secret scanning
- SBOM generation

**Security Context:**

- Non-root containers
- Read-only filesystem
- Dropped capabilities
- Security contexts

### Testing Strategy

**Test Types:**

1. **Unit Tests** - Fast, isolated
2. **Integration Tests** - Component interaction
3. **E2E Tests** - Full deployment in Kubernetes

**Test Execution:**

- Local: `make test`, `make e2e-tests`
- CI: Automatic on PRs
- CD: With production artifacts

### Deployment

**Deployment Method:**

- Helm charts for Kubernetes
- OCI registry (GHCR)
- Immutable versions
- Signed artifacts

**Deployment Targets:**

- Kubernetes clusters
- NKP (Nutanix Kubernetes Platform)
- Supports Gateway API and Traefik

## AI Agent Best Practices

### 1. Code Understanding

**Before Making Changes:**

- Read related code
- Understand dependencies
- Check existing patterns
- Review tests

**When Analyzing:**

- Start with `README.md`
- Check `Makefile` for build process
- Review `docs/` for context
- Understand CI/CD workflows

### 2. Making Safe Changes

**Guidelines:**

- Follow existing patterns
- Maintain test coverage
- Update documentation
- Consider security implications
- Test locally first

**Validation:**

- Run `make test` locally
- Check `make lint` passes
- Verify builds work
- Test deployment if needed

### 3. Documentation Updates

**When to Update:**

- Adding new features
- Changing workflows
- Updating dependencies
- Security changes

**Documentation Files:**

- `README.md` - Project overview
- `docs/*.md` - Detailed documentation
- Code comments - Inline documentation

### 4. CI/CD Awareness

**Understand:**

- What runs on PRs
- What runs on master
- What artifacts are created
- What security checks exist

**When Making Changes:**

- Consider CI impact
- Ensure tests will pass
- Check security scans
- Verify deployments

## Key Commands for AI Agents

### Local Development

```bash
# Setup
make deps              # Download dependencies
make build             # Build binary
make test              # Run all tests
make e2e-tests         # Run e2e tests

# Docker
make docker-build      # Build Docker image
make docker-push       # Push image (requires auth)

# Helm
make helm-chart        # Package chart
make push-helm-chart   # Push chart (requires auth)

# Security
make check-secrets     # Check for secrets
make kubesec           # Security scan
```

### CI/CD Simulation

```bash
# Run CI steps locally
make deps
make lint
make test
make docker-build
make helm-chart
make kubesec
```

## Repository Metadata

### Technology Stack

- **Language:** Go 1.25
- **Container:** Cloud Native Buildpacks
- **Orchestration:** Kubernetes
- **Package Manager:** Helm
- **Registry:** GHCR (OCI)
- **CI/CD:** GitHub Actions

### Key Dependencies

- **Go Modules:** See `go.mod`
- **Helm Chart:** See `chart/dm-nkp-gitops-custom-app/Chart.yaml`
- **Buildpacks:** Google builder (gcr.io/buildpacks/builder:google-22)

### Important URLs

- **Repository:** <https://github.com/deepak-muley/dm-nkp-gitops-custom-app>
- **Packages:** <https://github.com/users/deepak-muley/packages>
- **Actions:** <https://github.com/deepak-muley/dm-nkp-gitops-custom-app/actions>

## Workflow Triggers

### CI Workflow

- **PRs:** All pull requests (any target branch)
- **Pushes:** main, master, develop, dev branches

### CD Workflow

- **Pushes:** master branch only
- **Tags:** v* (e.g., v1.0.0)

### Security Workflow

- **PRs:** All pull requests
- **Pushes:** main, master, develop, dev
- **Schedule:** Daily at 2 AM UTC

### Other Workflows

- **Release:** On version tags, manual dispatch
- **Stale:** Daily schedule, manual dispatch
- **Auto-merge:** On PR events
- **Label:** On PR/Issue events
- **Performance:** On PRs to main/master, pushes

## AI Agent Interaction Examples

### Example 1: Adding a New Feature

**AI Agent Should:**

1. Understand current code structure
2. Check existing patterns
3. Add feature following conventions
4. Add/update tests
5. Update documentation if needed
6. Ensure CI will pass

**Files to Consider:**

- Feature code in `internal/`
- Tests in same package or `tests/`
- Documentation in `docs/`
- CI/CD workflows if deployment changes

### Example 2: Fixing a Bug

**AI Agent Should:**

1. Understand the bug
2. Locate relevant code
3. Check existing tests
4. Fix the issue
5. Add test if missing
6. Verify fix works

**Debugging Steps:**

- Check error messages
- Review related code
- Run tests locally
- Check CI logs

### Example 3: Updating Dependencies

**AI Agent Should:**

1. Check current versions
2. Review changelogs
3. Update dependencies
4. Run tests
5. Check for breaking changes
6. Update documentation if needed

**Process:**

- Update `go.mod`
- Run `make deps`
- Run `make test`
- Check security scans

## Important Notes for AI Agents

### 1. Branch Strategy

- **`master`** - Production branch (protected)
- **`dev`** - Development branch
- **Feature branches** - Created from `dev`

### 2. Versioning

- Uses immutable versioning with Git SHA
- Prevents artifact overwrites
- Enables traceability

### 3. Security

- All production images are signed
- Security scans run automatically
- Secrets are checked in CI

### 4. Testing

- Tests must pass before merge
- E2E tests validate deployment
- Coverage tracked in Codecov

### 5. Documentation

- Comprehensive docs in `docs/`
- README for quick start
- Inline code comments

## Quick Reference

### Key Files

- `Makefile` - Build automation
- `go.mod` - Dependencies
- `.github/workflows/` - CI/CD
- `chart/` - Helm chart
- `docs/` - Documentation

### Key Commands

- `make help` - Show all targets
- `make test` - Run tests
- `make build` - Build binary
- `make e2e-tests` - Run e2e tests

### Key Workflows

- CI - Testing and validation
- CD - Deployment
- Security - Security scanning
- Release - Release automation

## Additional Resources

- [CI/CD Pipeline Documentation](./cicd-pipeline.md)
- [GitHub Actions Reference](./github-actions-reference.md)
- [Testing Guide](./testing.md)
- [Security Documentation](./security.md)
- [Image Signing](./image-signing.md)
- [Helm Deployment](./helm-deployment.md)

## AI Agent Capabilities

This repository is designed to work well with AI agents by:

- ✅ Clear structure and organization
- ✅ Comprehensive documentation
- ✅ Automated testing and validation
- ✅ Consistent patterns and conventions
- ✅ Well-documented workflows
- ✅ Clear error messages
- ✅ Helpful Makefile targets

## Tips for AI Agents

1. **Read First:** Always read relevant documentation before making changes
2. **Test Locally:** Run tests locally before pushing
3. **Follow Patterns:** Maintain consistency with existing code
4. **Update Docs:** Keep documentation current
5. **Check CI:** Understand what CI will validate
6. **Security First:** Consider security implications
7. **Ask Questions:** When uncertain, ask for clarification

---

**Last Updated:** $(date)  
**Repository:** dm-nkp-gitops-custom-app  
**Purpose:** Reference implementation for NKP with production-ready CI/CD
