# GitHub Actions Setup Guide

Complete setup guide for all GitHub Actions workflows in this repository.

## Overview

This repository includes **8 workflows** covering:
- ✅ CI/CD (build, test, deploy)
- ✅ Security scanning (CodeQL, Trivy, SBOM)
- ✅ Release automation
- ✅ Dependency management (Dependabot)
- ✅ Quality assurance (performance, labeling)
- ✅ Maintenance (stale management)

## Quick Setup (5 minutes)

### 1. Enable Security Features

Go to: **Settings → Security → Code security and analysis**

Enable:
- ✅ Dependency graph
- ✅ Dependabot alerts
- ✅ Dependabot security updates
- ✅ Code scanning (CodeQL)

### 2. Set Required Secrets

Go to: **Settings → Secrets and variables → Actions**

Add:
- `CODECOV_TOKEN` - Get from https://codecov.io/gh/deepak-muley/dm-nkp-gitops-custom-app
- (Optional) `FOSSA_API_KEY` - For license scanning

### 3. Verify Workflows

1. Go to **Actions** tab
2. Verify all workflows are listed
3. Create a test PR to trigger workflows

## Detailed Setup

### Security Scanning Setup

#### CodeQL
1. **Automatic:** Enabled via workflow
2. **Manual Setup:**
   - Settings → Security → Code scanning
   - Enable CodeQL analysis
   - Select language: Go

#### Container Scanning (Trivy)
- **Automatic:** Runs in security workflow
- **Results:** Uploaded to GitHub Security tab
- **Format:** SARIF

#### SBOM Generation
- **Automatic:** Generated in security workflow
- **Format:** SPDX-JSON
- **Storage:** GitHub Actions artifacts (30 days)

### Dependabot Setup

**File:** `.github/dependabot.yml`

**Already configured for:**
- Go modules (weekly)
- GitHub Actions (weekly)
- Docker images (weekly)

**Customization:**
- Edit `.github/dependabot.yml`
- Adjust schedule, labels, reviewers

### Release Automation Setup

**File:** `.github/workflows/release.yml`

**Automatic releases:**
```bash
# Create and push a version tag
git tag v1.0.0
git push origin v1.0.0
# Release workflow runs automatically
```

**Manual releases:**
1. Go to Actions → Release
2. Click "Run workflow"
3. Enter version (e.g., `1.0.0`)

### Auto-merge Setup

**File:** `.github/workflows/auto-merge.yml`

**Requirements:**
- Branch protection must allow auto-merge
- PR must have `dependencies` label
- All status checks must pass

**Enable in branch protection:**
- Settings → Branches → master
- Enable "Allow auto-merge"

### Label Management Setup

**Files:**
- `.github/labeler.yml` - File-based labels
- `.github/labeler-size.yml` - Size-based labels

**Automatic:** Labels applied on PR creation

**Customization:**
- Edit labeler config files
- Add/remove label patterns

## Workflow Status

### Viewing Workflow Status

**In Repository:**
- Actions tab → View all runs
- Security tab → View security scans
- Dependencies tab → View dependency updates

**In PRs:**
- Status checks show at bottom of PR
- Codecov comment shows coverage
- Security alerts show in Security tab

### Status Badges

Add to README.md:

```markdown
## CI/CD Status

![CI](https://github.com/deepak-muley/dm-nkp-gitops-custom-app/workflows/CI/badge.svg)
![CD](https://github.com/deepak-muley/dm-nkp-gitops-custom-app/workflows/CD/badge.svg)
![Security](https://github.com/deepak-muley/dm-nkp-gitops-custom-app/workflows/Security%20Scanning/badge.svg)
![CodeQL](https://github.com/deepak-muley/dm-nkp-gitops-custom-app/workflows/CodeQL/badge.svg)
```

## Verification Checklist

After setup, verify:

- [ ] CI workflow runs on PRs
- [ ] CD workflow runs on master push
- [ ] Security scans run on PRs
- [ ] CodeQL results appear in Security tab
- [ ] Dependabot creates PRs weekly
- [ ] Labels are applied to PRs
- [ ] Codecov comments appear in PRs
- [ ] Release workflow creates releases on tags

## Troubleshooting

### Workflows Not Running

**Check:**
1. Workflow files are in `.github/workflows/`
2. YAML syntax is valid
3. Workflow is enabled in Actions tab
4. Branch protection allows workflows

### Security Scans Not Appearing

**Check:**
1. Security features enabled in Settings
2. CodeQL enabled in Security tab
3. Workflow has correct permissions
4. SARIF files are uploaded

### Dependabot Not Creating PRs

**Check:**
1. `.github/dependabot.yml` exists
2. Dependabot enabled in Settings
3. Repository has dependencies
4. Schedule has passed

### Auto-merge Not Working

**Check:**
1. Branch protection allows auto-merge
2. PR has `dependencies` label
3. All status checks pass
4. Workflow has `pull-requests: write` permission

## Advanced Configuration

### Customize Security Scans

Edit `.github/workflows/security.yml`:
- Adjust Trivy severity levels
- Change SBOM format
- Add custom security tools

### Customize Release Process

Edit `.github/workflows/release.yml`:
- Change changelog format
- Add release artifacts
- Customize release notes

### Customize Labels

Edit `.github/labeler.yml`:
- Add new label patterns
- Change label names
- Adjust file matching rules

## Monitoring and Maintenance

### Weekly Tasks
- Review Dependabot PRs
- Check security alerts
- Review stale issues/PRs

### Monthly Tasks
- Review workflow performance
- Update workflow actions
- Review and adjust configurations

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [CodeQL Documentation](https://codeql.github.com/docs/)
- [Dependabot Documentation](https://docs.github.com/en/code-security/dependabot)
- [Workflow Reference](./github-actions-reference.md)
- [CI/CD Pipeline](./cicd-pipeline.md)

