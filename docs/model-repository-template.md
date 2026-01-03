# Model Repository Template Guide

This document provides a comprehensive guide to all standard files, templates, and configurations needed to create a production-ready, model repository. Use this as a reference when setting up new repositories.

## Table of Contents

- [Overview](#overview)
- [Root-Level Files](#root-level-files)
- [GitHub Configuration](#github-configuration)
- [Documentation Structure](#documentation-structure)
- [CI/CD Workflows](#cicd-workflows)
- [Code Quality](#code-quality)
- [Replication Checklist](#replication-checklist)

## Overview

A model repository should include:

- ✅ Legal and compliance files (LICENSE, SECURITY.md, CODE_OF_CONDUCT.md)
- ✅ Community health files (CONTRIBUTING.md, CHANGELOG.md)
- ✅ GitHub templates (Issues, PRs, CODEOWNERS)
- ✅ Pre-commit hooks for code quality
- ✅ Comprehensive CI/CD pipelines
- ✅ Security scanning and automation
- ✅ Architecture documentation (ADRs)
- ✅ Troubleshooting guides

## Root-Level Files

### 1. LICENSE

**Purpose**: Legal license for the project  
**Format**: Apache 2.0 (recommended for open source)  
**Location**: `/LICENSE`  
**Template**: Standard Apache 2.0 license text  
**Customization**: Update copyright year and owner name

**Key Sections**:

- Terms and conditions
- Grant of copyright license
- Grant of patent license
- Redistribution rules
- Disclaimer of warranty

### 2. SECURITY.md

**Purpose**: Security policy and vulnerability reporting  
**Location**: `/SECURITY.md`  
**Template**: See `SECURITY.md` in this repository

**Required Sections**:

- Supported versions table
- Reporting process (email + GitHub Security Advisories)
- Response timeline
- Disclosure policy
- Security scanning information
- Security checklist

**Customization Points**:

- Replace `security@yourdomain.com` with actual security contact
- Update supported versions
- Add project-specific security practices

### 3. CODE_OF_CONDUCT.md

**Purpose**: Community standards and behavior guidelines  
**Location**: `/CODE_OF_CONDUCT.md`  
**Template**: Contributor Covenant 2.1 (standard)

**Required Sections**:

- Our Pledge
- Our Standards (positive and negative examples)
- Enforcement Responsibilities
- Scope
- Enforcement Guidelines (Correction, Warning, Temporary Ban, Permanent Ban)

**Customization Points**:

- Update contact method for reporting
- Add project-specific community guidelines

### 4. CONTRIBUTING.md

**Purpose**: Guide for contributors  
**Location**: `/CONTRIBUTING.md`  
**Template**: See `CONTRIBUTING.md` in this repository

**Required Sections**:

- Development setup
- Making changes process
- Commit message format (Conventional Commits)
- Pull request process
- Code style guidelines
- Testing requirements

### 5. CHANGELOG.md

**Purpose**: Record of all changes  
**Location**: `/CHANGELOG.md`  
**Format**: [Keep a Changelog](https://keepachangelog.com/) format  
**Template**: See `CHANGELOG.md` in this repository

**Required Sections**:

- [Unreleased] section
- Version sections with dates
- Change categories: Added, Changed, Deprecated, Removed, Fixed, Security

**Format**:

```markdown
## [Unreleased]

### Added
- New feature 1
- New feature 2

### Changed
- Improvement 1

## [1.0.0] - 2024-01-01

### Added
- Initial release
```

### 6. README.md

**Purpose**: Project overview and quick start  
**Location**: `/README.md`  
**Template**: See `README.md` in this repository

**Required Sections**:

- Project description
- Badges (CI/CD, License, Version, etc.)
- Features list
- Quick start
- Project structure
- Documentation links
- Contributing guide

**Badges to Include**:

```markdown
[![CI](https://github.com/owner/repo/workflows/CI/badge.svg)](link)
[![CD](https://github.com/owner/repo/workflows/CD/badge.svg)](link)
[![Security](https://github.com/owner/repo/workflows/Security/badge.svg)](link)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Go Version](https://img.shields.io/badge/go-1.x-blue.svg)](link)
```

## GitHub Configuration

### 1. Issue Templates

**Location**: `.github/ISSUE_TEMPLATE/`  
**Files Required**:

- `bug_report.md`
- `feature_request.md`
- `question.md`
- `config.yml`

#### Bug Report Template

**Required Fields**:

- Bug description
- Steps to reproduce
- Expected vs actual behavior
- Environment details
- Logs
- Configuration
- Checklist

**Template Structure**:

```markdown
---
name: Bug Report
about: Create a report to help us improve
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description
## Steps to Reproduce
## Expected Behavior
## Actual Behavior
## Environment
## Logs
## Configuration
## Additional Context
## Checklist
```

#### Feature Request Template

**Required Fields**:

- Feature description
- Problem statement
- Proposed solution
- Alternatives considered
- Benefits
- Implementation notes

#### Question Template

**Required Fields**:

- Question
- Context
- What you've tried
- Related documentation checklist

#### Template Configuration

**File**: `.github/ISSUE_TEMPLATE/config.yml`

**Required Sections**:

- `blank_issues_enabled: false` (force template use)
- Contact links (Security, Documentation)

### 2. Pull Request Template

**Location**: `.github/PULL_REQUEST_TEMPLATE.md`

**Required Sections**:

- Description
- Type of change (checkboxes)
- Related issues
- Changes made
- Testing checklist
- General checklist
- Screenshots (if applicable)
- Deployment notes
- Reviewer notes

**Change Types**:

- 🐛 Bug fix
- ✨ New feature
- 💥 Breaking change
- 📚 Documentation
- 🔧 Refactoring
- ⚡ Performance
- 🧪 Test update
- 🔒 Security fix

### 3. CODEOWNERS

**Location**: `.github/CODEOWNERS`  
**Purpose**: Automatic reviewer assignment

**Structure**:

```
# Global owners
* @owner1 @owner2

# Specific paths
/docs/ @owner1
/.github/ @owner1 @owner2
*.go @owner1
```

**Patterns**:

- `*` - All files
- `/path/` - Directory
- `*.ext` - File extension
- `#` - Comments

### 4. Dependabot Configuration

**Location**: `.github/dependabot.yml`

**Required Sections**:

- Version (always `2`)
- Updates array with:
  - Package ecosystem (gomod, github-actions, docker)
  - Directory
  - Schedule (interval, day, time)
  - Open PR limit
  - Labels
  - Commit message format
  - Reviewers/assignees

**Example**:

```yaml
version: 2
updates:
  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
      - "go"
```

### 5. Labeler Configuration

**Location**:

- `.github/labeler.yml` (file-based labels)
- Size-based labeling (implemented via GitHub script in label.yml workflow)

**Purpose**: Auto-label PRs based on files changed

**Structure**:

```yaml
docs:
  - 'docs/**/*'
  - '*.md'

go:
  - '**/*.go'
  - 'go.mod'
```

## Pre-Commit Hooks

### Configuration

**Location**: `.pre-commit-config.yaml`

**Required Hooks**:

- `pre-commit-hooks` (trailing whitespace, end-of-file, YAML/JSON check)
- `pre-commit-golang` (go-fmt, go-vet, golangci-lint)
- `detect-secrets` (secret scanning)
- `markdownlint-cli` (markdown linting)
- `shellcheck-py` (shell script linting)
- `yamllint` (YAML linting)

**Installation**:

```bash
pip install pre-commit
pre-commit install
```

**Usage**:

```bash
pre-commit run --all-files  # Run on all files
pre-commit run              # Run on staged files
```

## Documentation Structure

### 1. Architecture Decision Records (ADRs)

**Location**: `docs/adr/`  
**Naming**: `NNNN-title-in-kebab-case.md`  
**Numbering**: Sequential, starting at 0001

**Template**:

```markdown
# ADR-NNNN: Title

## Status

[Proposed | Accepted | Deprecated | Superseded by ADR-XXXX]

## Context

[Describe the issue motivating this decision]

## Decision

[Describe the change we're proposing or have agreed to implement]

## Consequences

[Describe the consequences of this decision]
```

**Required ADRs**:

- ADR-0001: Record Architecture Decisions (meta-ADR)
- ADR-0002: Technology choices (buildpacks, etc.)
- ADR-0003: Versioning strategy
- ADR-0004: Deployment patterns

### 2. Troubleshooting Guide

**Location**: `docs/TROUBLESHOOTING.md`

**Required Sections**:

- Build issues
- Deployment issues
- CI/CD issues
- Testing issues
- Security issues
- Performance issues
- Common commands
- Getting help

### 3. CI/CD Documentation

**Required Documents**:

- `docs/cicd-pipeline.md` - Complete pipeline documentation
- `docs/github-actions-reference.md` - All workflows documented
- `docs/github-actions-setup.md` - Setup guide
- `docs/github-actions-summary.md` - Quick reference

### 4. Development Documentation

**Required Documents**:

- `docs/development.md` - Development setup
- `docs/testing.md` - Testing guide
- `docs/deployment.md` - Deployment guide
- `docs/security.md` - Security practices

## CI/CD Workflows

### 1. CI Workflow

**Location**: `.github/workflows/ci.yml`

**Required Jobs**:

- `test` - Unit and integration tests
- `docker-build` - Build Docker images (PRs only)
- `helm` - Package and validate Helm charts (PRs only)
- `e2e` - End-to-end tests
- `build` - Build binaries
- `kubesec` - Security scanning

**Key Features**:

- Runs on all PRs
- Runs on pushes to main branches
- Uploads coverage to Codecov
- Builds artifacts for testing
- Pushes to `/dev` registry path for PRs

### 2. CD Workflow

**Location**: `.github/workflows/cd.yml`

**Required Jobs**:

- `build-and-push` - Build, sign, push artifacts
- `e2e` - Test production artifacts

**Key Features**:

- Runs only on master branch
- Signs images with cosign
- Pushes to production registry path
- Immutable versioning

### 3. Security Workflow

**Location**: `.github/workflows/security.yml`

**Required Jobs**:

- `codeql` - Static code analysis
- `container-scan` - Trivy vulnerability scanning
- `sbom` - SBOM generation
- `dependency-review` - Dependency checking
- `license-scan` - License compliance

**Key Features**:

- Runs on PRs, pushes, and daily schedule
- Uploads results to GitHub Security tab
- Generates SBOM artifacts

### 4. Release Workflow

**Location**: `.github/workflows/release.yml`

**Key Features**:

- Triggers on version tags
- Manual dispatch option
- Generates changelog
- Creates GitHub release
- Includes artifact references

### 5. Automation Workflows

**Additional Workflows**:

- `stale.yml` - Manage stale issues/PRs
- `auto-merge.yml` - Auto-merge Dependabot PRs
- `label.yml` - Auto-label PRs/issues
- `performance.yml` - Performance testing
- `release.yml` - Release automation

## Code Quality

### 1. Linting Configuration

**Location**: `.golangci.yml` (for Go projects)

**Required Linters**:

- `errcheck` - Error checking
- `gosimple` - Simplification suggestions
- `govet` - Go vet
- `staticcheck` - Static analysis
- `gofmt` - Formatting
- `goimports` - Import formatting
- `misspell` - Spelling
- `gocyclo` - Cyclomatic complexity
- `dupl` - Duplicate code detection

### 2. Code Coverage

**Configuration**: `codecov.yml`

**Required Settings**:

- Coverage status thresholds
- File paths
- Flags for different test types
- Ignore patterns

### 3. Makefile

**Location**: `/Makefile`

**Required Targets**:

- `help` - Show all targets
- `deps` - Download dependencies
- `build` - Build application
- `test` - Run tests
- `lint` - Run linters
- `docker-build` - Build Docker image
- `docker-push` - Push Docker image
- `helm-chart` - Package Helm chart
- `e2e-tests` - Run e2e tests

**Pattern**:

```makefile
target: ## Description
 @command
```

## Replication Checklist

Use this checklist when setting up a new repository:

### Legal & Compliance

- [ ] Create LICENSE file (Apache 2.0)
- [ ] Create SECURITY.md with security contact
- [ ] Create CODE_OF_CONDUCT.md
- [ ] Update copyright in LICENSE

### Community Files

- [ ] Create CONTRIBUTING.md
- [ ] Create CHANGELOG.md
- [ ] Update README.md with badges
- [ ] Add project description and features

### GitHub Configuration

- [ ] Create `.github/ISSUE_TEMPLATE/` directory
- [ ] Create bug_report.md template
- [ ] Create feature_request.md template
- [ ] Create question.md template
- [ ] Create config.yml for templates
- [ ] Create PULL_REQUEST_TEMPLATE.md
- [ ] Create CODEOWNERS file
- [ ] Update CODEOWNERS with actual owners

### Pre-Commit Hooks

- [ ] Create `.pre-commit-config.yaml`
- [ ] Install pre-commit: `pip install pre-commit`
- [ ] Install hooks: `pre-commit install`
- [ ] Test hooks: `pre-commit run --all-files`

### Documentation

- [ ] Create `docs/adr/` directory
- [ ] Create ADR-0001 (meta-ADR)
- [ ] Create ADR-0002+ (technology decisions)
- [ ] Create TROUBLESHOOTING.md
- [ ] Create CI/CD documentation
- [ ] Create development guide
- [ ] Create deployment guide

### CI/CD Workflows

- [ ] Create `.github/workflows/ci.yml`
- [ ] Create `.github/workflows/cd.yml`
- [ ] Create `.github/workflows/security.yml`
- [ ] Create `.github/workflows/release.yml`
- [ ] Create `.github/workflows/stale.yml`
- [ ] Create `.github/workflows/auto-merge.yml`
- [ ] Create `.github/workflows/label.yml`
- [ ] Create `.github/workflows/performance.yml` (optional)

### Dependabot

- [ ] Create `.github/dependabot.yml`
- [ ] Configure for Go modules
- [ ] Configure for GitHub Actions
- [ ] Configure for Docker (if applicable)

### Labeler

- [ ] Create `.github/labeler.yml`
- [ ] Size-based labeling (implemented in label.yml workflow, no separate config file needed)
- [ ] Configure file-based labels
- [ ] Configure size-based labels

### Code Quality

- [ ] Create `.golangci.yml` (for Go)
- [ ] Create `codecov.yml`
- [ ] Update Makefile with standard targets
- [ ] Configure linting in CI

### Security

- [ ] Enable GitHub Security features
- [ ] Set up CodeQL
- [ ] Configure secret scanning
- [ ] Set up dependency alerts
- [ ] Configure image signing

### Testing

- [ ] Set up unit tests
- [ ] Set up integration tests
- [ ] Set up e2e tests
- [ ] Configure coverage reporting
- [ ] Set up Codecov

### Final Steps

- [ ] Review all templates for project-specific customization
- [ ] Update all placeholder values (emails, names, etc.)
- [ ] Test all workflows
- [ ] Verify all documentation links
- [ ] Create initial release
- [ ] Update CHANGELOG.md

## Customization Guide

### Project-Specific Customizations

1. **Language-Specific**:
   - Replace Go-specific configs with your language
   - Update linting tools
   - Adjust test frameworks

2. **Registry-Specific**:
   - Update registry paths
   - Adjust image naming
   - Configure authentication

3. **Deployment-Specific**:
   - Update Kubernetes manifests
   - Adjust Helm chart structure
   - Configure ingress/ingressroute

4. **Team-Specific**:
   - Update CODEOWNERS with team members
   - Adjust review requirements
   - Customize labels

## Template Files Reference

All template files are available in this repository:

- **Root Files**: LICENSE, SECURITY.md, CODE_OF_CONDUCT.md, CHANGELOG.md, CONTRIBUTING.md
- **GitHub Templates**: `.github/ISSUE_TEMPLATE/`, `.github/PULL_REQUEST_TEMPLATE.md`
- **Configuration**: `.github/CODEOWNERS`, `.github/dependabot.yml`, `.pre-commit-config.yaml`
- **Documentation**: `docs/adr/`, `docs/TROUBLESHOOTING.md`
- **Workflows**: `.github/workflows/*.yml`

## Best Practices

1. **Start Small**: Begin with essential files (LICENSE, README, CONTRIBUTING)
2. **Iterate**: Add more templates and automation over time
3. **Customize**: Adapt templates to your project's needs
4. **Maintain**: Keep templates updated as practices evolve
5. **Document**: Document any project-specific decisions

## Additional Resources

- [GitHub Community Health Files](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions)
- [Keep a Changelog](https://keepachangelog.com/)
- [Contributor Covenant](https://www.contributor-covenant.org/)
- [Architecture Decision Records](https://adr.github.io/)
- [Pre-commit Hooks](https://pre-commit.com/)

---

**Last Updated**: 2024  
**Repository**: dm-nkp-gitops-custom-app  
**Purpose**: Reference implementation for model repositories
