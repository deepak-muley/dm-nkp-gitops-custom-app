# Repository Replication Checklist

Quick reference checklist for setting up a new model repository. See [Model Repository Template Guide](model-repository-template.md) for detailed information.

## Quick Start

1. Copy files from this repository
2. Customize placeholders
3. Follow this checklist

## Files to Create

### Root Level (Required)
- [ ] `LICENSE` - Apache 2.0 license
- [ ] `SECURITY.md` - Security policy (update email)
- [ ] `CODE_OF_CONDUCT.md` - Contributor Covenant
- [ ] `CONTRIBUTING.md` - Contribution guidelines
- [ ] `CHANGELOG.md` - Change log
- [ ] `README.md` - Project overview (add badges)

### GitHub Configuration (Required)
- [ ] `.github/ISSUE_TEMPLATE/bug_report.md`
- [ ] `.github/ISSUE_TEMPLATE/feature_request.md`
- [ ] `.github/ISSUE_TEMPLATE/question.md`
- [ ] `.github/ISSUE_TEMPLATE/config.yml`
- [ ] `.github/PULL_REQUEST_TEMPLATE.md`
- [ ] `.github/CODEOWNERS` (update owners)
- [ ] `.github/dependabot.yml`
- [ ] `.github/labeler.yml`
- [ ] Size-based labeling (implemented in label.yml workflow)

### Pre-Commit Hooks (Recommended)
- [ ] `.pre-commit-config.yaml`
- [ ] Install: `pip install pre-commit && pre-commit install`

### Documentation (Recommended)
- [ ] `docs/adr/0001-record-architecture-decisions.md`
- [ ] `docs/adr/0002-*.md` (technology decisions)
- [ ] `docs/TROUBLESHOOTING.md`
- [ ] `docs/model-repository-template.md` (this guide)

### CI/CD Workflows (Required)
- [ ] `.github/workflows/ci.yml`
- [ ] `.github/workflows/cd.yml`
- [ ] `.github/workflows/security.yml`
- [ ] `.github/workflows/release.yml`
- [ ] `.github/workflows/stale.yml`
- [ ] `.github/workflows/auto-merge.yml`
- [ ] `.github/workflows/label.yml`
- [ ] `.github/workflows/performance.yml` (optional)

### Code Quality (Language-Specific)
- [ ] `.golangci.yml` (for Go projects)
- [ ] `codecov.yml`
- [ ] Update `Makefile` with standard targets

## Customization Checklist

### Update Placeholders
- [ ] Replace `security@yourdomain.com` in SECURITY.md
- [ ] Update copyright in LICENSE
- [ ] Update CODEOWNERS with actual GitHub usernames
- [ ] Update repository URLs in badges
- [ ] Update registry paths in workflows
- [ ] Update app name in all files

### Configure Secrets
- [ ] Set `CODECOV_TOKEN` in repository secrets
- [ ] Set `FOSSA_API_KEY` (optional) in repository secrets
- [ ] Verify `GITHUB_TOKEN` permissions

### Enable Features
- [ ] Enable Dependency graph in Settings → Security
- [ ] Enable Dependabot alerts
- [ ] Enable Code scanning (CodeQL)
- [ ] Enable Secret scanning
- [ ] Configure branch protection rules

### Test Everything
- [ ] Test pre-commit hooks: `pre-commit run --all-files`
- [ ] Create test PR to verify templates
- [ ] Verify CI workflows run
- [ ] Verify CD workflow runs on master
- [ ] Test security scans
- [ ] Verify labels are applied
- [ ] Test auto-merge (if enabled)

## File Structure Summary

```
.
├── LICENSE
├── SECURITY.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── CHANGELOG.md
├── README.md
├── .pre-commit-config.yaml
├── .golangci.yml (Go projects)
├── codecov.yml
├── Makefile
├── .github/
│   ├── CODEOWNERS
│   ├── dependabot.yml
│   ├── labeler.yml
│   ├── labeler-size.yml
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   ├── feature_request.md
│   │   ├── question.md
│   │   └── config.yml
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/
│       ├── ci.yml
│       ├── cd.yml
│       ├── security.yml
│       ├── release.yml
│       ├── stale.yml
│       ├── auto-merge.yml
│       ├── label.yml
│       └── performance.yml
└── docs/
    ├── adr/
    │   ├── 0001-record-architecture-decisions.md
    │   └── ...
    ├── TROUBLESHOOTING.md
    └── model-repository-template.md
```

## Quick Copy Commands

```bash
# Copy root files
cp LICENSE SECURITY.md CODE_OF_CONDUCT.md CONTRIBUTING.md CHANGELOG.md /path/to/new-repo/

# Copy GitHub configuration
cp -r .github /path/to/new-repo/

# Copy pre-commit config
cp .pre-commit-config.yaml /path/to/new-repo/

# Copy documentation
cp -r docs/adr /path/to/new-repo/docs/
cp docs/TROUBLESHOOTING.md /path/to/new-repo/docs/
cp docs/model-repository-template.md /path/to/new-repo/docs/
```

## Essential Customizations

1. **SECURITY.md**: Update email address
2. **CODEOWNERS**: Replace with actual team members
3. **LICENSE**: Update copyright year and owner
4. **README.md**: Update badges with your repository
5. **Workflows**: Update registry paths and app names
6. **Dependabot**: Adjust schedule and labels as needed

## Time Estimate

- **Basic Setup** (root files + GitHub templates): 30 minutes
- **Full Setup** (including CI/CD + documentation): 2-3 hours
- **Customization** (project-specific): 1-2 hours

**Total**: ~4-5 hours for complete setup

## Support

For questions or issues:
- Review [Model Repository Template Guide](model-repository-template.md)
- Check [Troubleshooting Guide](TROUBLESHOOTING.md)
- Open an issue in this repository

---

**Last Updated**: 2024  
**Source Repository**: dm-nkp-gitops-custom-app

