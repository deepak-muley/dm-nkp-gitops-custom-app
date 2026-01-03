# GitHub Actions Summary

This document provides a quick reference of all GitHub Actions workflows configured for this repository.

## Complete Workflow List

### Core CI/CD Workflows

1. **CI** (`.github/workflows/ci.yml`)
   - Runs on: All PRs, pushes to main/master/dev
   - Purpose: Build, test, validate
   - Jobs: test, e2e, build, docker-build, helm, kubesec

2. **CD** (`.github/workflows/cd.yml`)
   - Runs on: Pushes to master, version tags
   - Purpose: Build, sign, push artifacts
   - Jobs: build-and-push, e2e

### Security Workflows

3. **Security Scanning** (`.github/workflows/security.yml`)
   - Runs on: PRs, pushes, daily schedule
   - Purpose: Comprehensive security scanning
   - Jobs: codeql, container-scan, sbom, dependency-review, license-scan

### Automation Workflows

4. **Release** (`.github/workflows/release.yml`)
   - Runs on: Version tags, manual dispatch
   - Purpose: Automated release creation
   - Jobs: release

5. **Stale Management** (`.github/workflows/stale.yml`)
   - Runs on: Daily schedule, manual dispatch
   - Purpose: Mark and close stale issues/PRs
   - Jobs: stale

6. **Auto-merge** (`.github/workflows/auto-merge.yml`)
   - Runs on: PR events
   - Purpose: Auto-merge Dependabot PRs
   - Jobs: auto-merge

7. **Label Management** (`.github/workflows/label.yml`)
   - Runs on: PR/Issue events
   - Purpose: Auto-label PRs and issues
   - Jobs: label

### Quality Assurance Workflows

8. **Performance Testing** (`.github/workflows/performance.yml`)
   - Runs on: PRs to main/master, pushes
   - Purpose: Performance and resource testing
   - Jobs: load-test, resource-usage

## Configuration Files

- **Dependabot** (`.github/dependabot.yml`)
  - Automated dependency updates
  - Weekly schedule for Go, Actions, Docker

- **Labeler Config** (`.github/labeler.yml` for file-based labels, size-based labels via GitHub script)
  - Auto-labeling rules
  - File-based and size-based labels

- **Codecov** (`codecov.yml`)
  - Coverage reporting configuration

## Workflow Matrix

| Workflow | PR | Push | Schedule | Manual | Purpose |
|----------|----|----|----------|--------|---------|
| CI | ✅ | ✅ | ❌ | ❌ | Build & Test |
| CD | ❌ | ✅ (master) | ❌ | ❌ | Deploy |
| Security | ✅ | ✅ | ✅ (daily) | ❌ | Security Scan |
| Release | ❌ | ✅ (tags) | ❌ | ✅ | Create Release |
| Stale | ❌ | ❌ | ✅ (daily) | ✅ | Manage Stale |
| Auto-merge | ✅ | ❌ | ❌ | ❌ | Auto-merge |
| Label | ✅ | ❌ | ❌ | ❌ | Auto-label |
| Performance | ✅ | ✅ | ❌ | ✅ | Performance Test |

## Quick Setup Checklist

- [ ] Enable CodeQL in repository settings
- [ ] Enable Dependency graph
- [ ] Enable Dependabot alerts
- [ ] Set `CODECOV_TOKEN` secret
- [ ] (Optional) Set `FOSSA_API_KEY` secret
- [ ] Review and adjust labeler configurations
- [ ] Test workflows with a sample PR

## Workflow Dependencies

```
PR Created
  ↓
CI Workflow (test, build, validate)
  ↓
Security Workflow (scan, SBOM)
  ↓
Label Workflow (auto-label)
  ↓
Auto-merge (if Dependabot)
  ↓
Merge to Master
  ↓
CD Workflow (build, push, sign)
  ↓
Release Workflow (if tagged)
```

## Best Practices Implemented

✅ **Security**
- CodeQL static analysis
- Container vulnerability scanning
- SBOM generation
- Dependency review
- Secret scanning

✅ **Automation**
- Automated releases
- Auto-merge dependencies
- Auto-labeling
- Stale management

✅ **Quality**
- Comprehensive testing
- Performance monitoring
- Resource usage tracking
- Code coverage

✅ **Developer Experience**
- Clear labels
- Automated changelogs
- Status badges
- Comprehensive docs

## Monitoring

View workflow status:
- **GitHub Actions Tab:** All workflow runs
- **Security Tab:** Security scan results
- **Dependencies Tab:** Dependency updates
- **Releases Tab:** Release history

## Troubleshooting

See [GitHub Actions Reference](./github-actions-reference.md#troubleshooting) for detailed troubleshooting.

## Next Steps

1. Enable security features in repository settings
2. Set up required secrets
3. Test workflows with sample PRs
4. Monitor workflow runs
5. Adjust configurations as needed

