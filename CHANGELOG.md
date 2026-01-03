# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive CI/CD pipeline with security scanning
- Automated dependency updates with Dependabot
- Pre-commit hooks for code quality (with Python venv support)
- Issue and PR templates
- Architecture Decision Records (ADRs)
- Troubleshooting guide
- Security policy (SECURITY.md)
- Code of Conduct
- LICENSE file (Apache 2.0)
- Model repository template documentation
- Replication checklist for new repositories
- Pre-commit setup documentation
- Registry path separation (dev vs production paths)
- Makefile targets for pre-commit hooks

### Changed
- Improved documentation structure
- Enhanced security scanning workflows
- Updated registry path separation (dev vs production)
- Makefile now auto-detects branch for registry path
- CI workflow pushes PR artifacts to `/dev` path
- CD workflow pushes master artifacts to main path

### Security
- Added CodeQL static analysis
- Added Trivy container scanning
- Added SBOM generation
- Enhanced secret scanning
- Pre-commit hooks for secret detection

## [0.1.0] - 2024-01-XX

### Added
- Initial release
- Go application with Prometheus metrics
- Health and readiness endpoints
- Helm chart for Kubernetes deployment
- CI/CD workflows
- Docker image building with buildpacks
- Image signing with cosign
- E2E testing framework
- Documentation

### Features
- Prometheus metrics export (Counter, Gauge, Histogram, Summary)
- Kubernetes deployment manifests
- Traefik IngressRoute support
- Gateway API HTTPRoute support
- Security-hardened container images
- Immutable versioning with Git SHA

[Unreleased]: https://github.com/deepak-muley/dm-nkp-gitops-custom-app/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/deepak-muley/dm-nkp-gitops-custom-app/releases/tag/v0.1.0
