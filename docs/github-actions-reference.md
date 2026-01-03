# GitHub Actions Reference

This document describes all GitHub Actions workflows configured for this repository, providing a comprehensive reference for building robust CI/CD pipelines.

## Workflow Overview

| Workflow | Trigger | Purpose | Frequency |
|----------|---------|---------|-----------|
| [CI](./cicd-pipeline.md#ci-workflow) | PR, Push | Build, test, validate | Every PR/Push |
| [CD](./cicd-pipeline.md#cd-workflow) | Master push | Deploy artifacts | On merge to master |
| [Security](./github-actions-reference.md#security-scanning) | PR, Push, Schedule | Security scanning | Daily + PRs |
| [Release](./github-actions-reference.md#release-automation) | Tags, Manual | Create releases | On version tags |
| [Stale](./github-actions-reference.md#stale-management) | Schedule | Manage stale issues/PRs | Daily |
| [Auto-merge](./github-actions-reference.md#auto-merge) | PR events | Auto-merge dependencies | On PR events |
| [Performance](./github-actions-reference.md#performance-testing) | PR, Push | Performance testing | On PR/Push |
| [Label](./github-actions-reference.md#label-management) | PR/Issue events | Auto-labeling | On PR/Issue events |

## Security Scanning

**File:** `.github/workflows/security.yml`

### Purpose
Comprehensive security scanning including:
- CodeQL static analysis
- Container image vulnerability scanning
- SBOM generation
- Dependency review
- License scanning
- OpenSSF Scorecard analysis

### Jobs

#### 1. CodeQL Security Analysis
- **Language:** Go
- **Frequency:** On every PR and push
- **Output:** Security alerts in GitHub Security tab
- **Permissions:** `security-events: write`

#### 2. Container Image Vulnerability Scanning
- **Tool:** Trivy
- **Scans:** Built Docker images
- **Output:** SARIF format uploaded to GitHub Security
- **Severity:** CRITICAL, HIGH, MEDIUM
- **Frequency:** On every PR and push

#### 3. SBOM Generation
- **Tool:** Syft
- **Format:** SPDX-JSON
- **Output:** Artifact uploaded, available for 30 days
- **Purpose:** Software Bill of Materials for supply chain security

#### 4. Dependency Review
- **Tool:** GitHub Dependency Review
- **Frequency:** On PRs only
- **Checks:**
  - Known vulnerabilities
  - License compliance
  - Security advisories
- **Fail on:** Moderate+ severity, denied licenses

#### 5. License Scanning
- **Tool:** FOSSA (optional)
- **Requires:** `FOSSA_API_KEY` secret (optional)
- **Purpose:** License compliance checking

#### 6. OpenSSF Scorecard Analysis
- **Tool:** OpenSSF Scorecard
- **Frequency:** On every PR, push, and daily schedule
- **Purpose:** Assess repository security posture and best practices
- **Checks:**
  - Security policy presence
  - Branch protection rules
  - Code review requirements
  - Dependency update tools
  - Automated security updates
  - Signed releases
  - Binary artifacts
  - Dangerous workflow patterns
  - Token permissions
  - And more (20+ checks)
- **Output:** SARIF format uploaded to GitHub Security tab
- **Publishing:** Results published to OpenSSF API for public repositories
- **Permissions:** Requires `id-token: write` for publishing results

### Configuration

```yaml
# Enable in repository settings
Settings → Security → Code security and analysis
- Enable: Dependency graph
- Enable: Dependabot alerts
- Enable: Dependabot security updates
- Enable: Code scanning
```

## Release Automation

**File:** `.github/workflows/release.yml`

### Purpose
Automated release creation with changelog generation.

### Triggers
- **Tags:** `v*.*.*` (e.g., `v1.0.0`)
- **Manual:** Workflow dispatch with version input

### Features
- Automatic changelog generation from commits
- Release notes with categorized changes
- Artifact references (Docker image, Helm chart)
- Pre-release detection (for `-alpha`, `-beta` tags)

### Usage

**Create release from tag:**
```bash
git tag v1.0.0
git push origin v1.0.0
# Release workflow runs automatically
```

**Create release manually:**
1. Go to Actions → Release → Run workflow
2. Enter version (e.g., `1.0.0`)
3. Workflow creates tag and release

## Stale Management

**File:** `.github/workflows/stale.yml`

### Purpose
Automatically mark and close stale issues and PRs.

### Configuration
- **Issues:** Stale after 60 days, closed after 7 more days
- **PRs:** Stale after 30 days, closed after 7 more days
- **Exemptions:**
  - Pinned issues/PRs
  - Security-related
  - Assigned items
  - Milestoned items

### Labels
- `stale` - Applied when item becomes stale
- Auto-closed if no activity

## Auto-merge

**File:** `.github/workflows/auto-merge.yml`

### Purpose
Automatically merge Dependabot PRs when all checks pass.

### Conditions
- PR author is `dependabot[bot]`
- PR has `dependencies` label
- All status checks pass
- PR is mergeable

### Merge Strategy
- **Method:** Squash merge
- **Auto-merge:** Enabled automatically

## Performance Testing

**File:** `.github/workflows/performance.yml`

### Purpose
Performance and resource usage testing.

### Jobs

#### 1. Load Testing
- Deploys application to kind cluster
- Runs basic load tests (100 requests)
- Measures average response time
- Fails if response time > 1 second

#### 2. Resource Usage Monitoring
- Checks Docker image size
- Warns if image > 500MB
- Reports resource metrics

### Frequency
- Runs on PRs to `main`/`master`
- Runs on pushes to `main`/`master`

## Label Management

**File:** `.github/workflows/label.yml`

### Purpose
Automatically label PRs and issues based on:
- Files changed
- PR size (lines changed)

### Label Categories

**By Files:**
- `docs` - Documentation changes
- `ci` - CI/CD changes
- `helm` - Helm chart changes
- `docker` - Dockerfile changes
- `go` - Go code changes
- `security` - Security-related changes
- `testing` - Test changes
- `scripts` - Script changes
- `config` - Configuration changes

**By Size:**
- `size/XS` - 1 file changed
- `size/S` - 2-9 files
- `size/M` - 10-29 files
- `size/L` - 30-99 files
- `size/XL` - 100+ files

**Note:** Size-based labeling uses a custom GitHub script (not labeler-size.yml) since `actions/labeler@v5` doesn't support size-based labeling natively.

## Dependabot Configuration

**File:** `.github/dependabot.yml`

### Purpose
Automated dependency updates.

### Ecosystems Monitored
- **Go modules** - Weekly updates
- **GitHub Actions** - Weekly updates
- **Docker** - Weekly updates

### Configuration
- **Schedule:** Weekly (Mondays, 9 AM)
- **PR Limit:** 10 for Go, 5 for Actions/Docker
- **Labels:** `dependencies`, ecosystem-specific
- **Reviewers:** Repository maintainers
- **Auto-merge:** Enabled via auto-merge workflow

## Best Practices Implemented

### 1. Security First
- ✅ CodeQL scanning
- ✅ Container vulnerability scanning
- ✅ SBOM generation
- ✅ Dependency review
- ✅ Secret scanning

### 2. Automation
- ✅ Automated releases
- ✅ Auto-merge for dependencies
- ✅ Auto-labeling
- ✅ Stale management

### 3. Quality Assurance
- ✅ Performance testing
- ✅ Resource monitoring
- ✅ Comprehensive testing (unit, integration, e2e)

### 4. Developer Experience
- ✅ Clear labels
- ✅ Automated changelogs
- ✅ Status badges
- ✅ Comprehensive documentation

## Workflow Status Badges

Add these badges to your README:

```markdown
![CI](https://github.com/deepak-muley/dm-nkp-gitops-custom-app/workflows/CI/badge.svg)
![CD](https://github.com/deepak-muley/dm-nkp-gitops-custom-app/workflows/CD/badge.svg)
![Security](https://github.com/deepak-muley/dm-nkp-gitops-custom-app/workflows/Security%20Scanning/badge.svg)
![CodeQL](https://github.com/deepak-muley/dm-nkp-gitops-custom-app/workflows/CodeQL/badge.svg)
```

## Required Secrets

| Secret | Purpose | Required For |
|--------|---------|--------------|
| `CODECOV_TOKEN` | Code coverage | CI workflow |
| `FOSSA_API_KEY` | License scanning | Security workflow (optional) |
| `GITHUB_TOKEN` | GitHub API access | All workflows (auto-provided) |

## Permissions

Workflows use minimal required permissions:
- `contents: read` - Read repository
- `contents: write` - Create releases
- `packages: write` - Push to GHCR
- `security-events: write` - Upload security scans
- `pull-requests: write` - Auto-merge, label
- `issues: write` - Stale management

## Scheduling

Scheduled workflows run at:
- **Security scans:** Daily at 2 AM UTC
- **Stale management:** Daily at 2 AM UTC
- **Dependabot:** Weekly on Mondays at 9 AM

## Troubleshooting

### Security Scans Fail

**Issue:** CodeQL or Trivy fails
**Solution:**
- Check GitHub Security tab for details
- Review SARIF results
- Fix identified vulnerabilities

### Auto-merge Not Working

**Issue:** Dependabot PRs not auto-merging
**Solution:**
- Verify PR has `dependencies` label
- Check all status checks pass
- Ensure branch protection allows auto-merge
- Verify workflow has `pull-requests: write` permission

### Release Not Created

**Issue:** Tag pushed but no release
**Solution:**
- Verify tag format: `v*.*.*`
- Check workflow permissions
- Review workflow logs

### Labels Not Applied

**Issue:** PRs not getting labels
**Solution:**
- Verify `.github/labeler.yml` exists
- Check workflow has `pull-requests: write` permission
- Review workflow logs

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [CodeQL Documentation](https://codeql.github.com/docs/)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [Dependabot Documentation](https://docs.github.com/en/code-security/dependabot)
- [CI/CD Pipeline Documentation](./cicd-pipeline.md)

