# CI/CD Pipeline Checklist

This document verifies that all requirements are met for the CI/CD pipeline.

## ✅ Completed Requirements

### 1. Local Development Workflow

- ✅ Users can build Helm chart locally: `make helm-chart`
- ✅ Users can build Docker image locally: `make docker-build`
- ✅ Users can run e2e tests locally: `make e2e-tests`
- ✅ All local commands documented in Makefile and docs

### 2. PR Workflow (CI)

- ✅ CI runs on ALL pull requests (any target branch)
- ✅ CI builds Docker image (test build, not pushed)
- ✅ CI packages Helm chart
- ✅ CI runs e2e tests using built Docker image and Helm chart
- ✅ CI runs unit tests, integration tests, linting
- ✅ CI checks for secrets
- ✅ CI runs security scans (kubesec)

### 3. Code Coverage

- ✅ Codecov integration configured
- ✅ Coverage reports uploaded to Codecov
- ✅ Codecov bot comments on PRs
- ✅ Coverage visible in PR status checks
- ✅ `codecov.yml` configuration file created

### 4. Master Branch Workflow (CD)

- ✅ CD runs only on pushes to master (not PRs)
- ✅ CD builds Docker image from master branch
- ✅ CD signs Docker image with cosign
- ✅ CD pushes Docker image to GHCR
- ✅ CD packages Helm chart from master branch
- ✅ CD pushes Helm chart to GHCR
- ✅ CD runs e2e tests using production artifacts from GHCR

### 5. Documentation

- ✅ Comprehensive CI/CD pipeline documentation created
- ✅ Workflow diagrams included
- ✅ Troubleshooting guide included
- ✅ Best practices documented

## ⚠️ Configuration Required

### GitHub Secrets

You need to set up the following secret in GitHub:

1. **CODECOV_TOKEN**
   - Go to: <https://codecov.io/gh/deepak-muley/dm-nkp-gitops-custom-app/settings>
   - Copy the repository upload token
   - Add to GitHub Secrets: Settings → Secrets and variables → Actions → New repository secret
   - Name: `CODECOV_TOKEN`
   - Value: Your Codecov token

### Codecov Setup

1. **Enable Codecov for Repository**
   - Visit: <https://codecov.io/gh/deepak-muley/dm-nkp-gitops-custom-app>
   - Sign in with GitHub
   - Enable the repository
   - Copy the upload token

2. **Verify Configuration**
   - Check that `codecov.yml` is in repository root
   - Verify token is set in GitHub Secrets
   - Run a test PR to verify Codecov comments appear

## 🔍 Verification Steps

### Test Local Development

```bash
# 1. Build Helm chart
make helm-chart
# Should create: chart/dm-nkp-gitops-custom-app-*.tgz

# 2. Build Docker image
make docker-build
# Should build image locally

# 3. Run e2e tests
make e2e-tests
# Should run e2e tests successfully
```

### Test PR Workflow

1. Create a test PR from `dev` to `master`
2. Verify CI runs automatically
3. Check that all jobs pass:
   - ✅ test
   - ✅ docker-build
   - ✅ helm
   - ✅ build
   - ✅ e2e
   - ✅ kubesec
4. Verify Codecov comment appears in PR
5. Check PR status checks show Codecov

### Test Master Workflow

1. Merge PR to master
2. Verify CD runs automatically
3. Check that jobs pass:
   - ✅ build-and-push (builds, signs, pushes artifacts)
   - ✅ e2e (tests production artifacts)
4. Verify artifacts in GHCR:
   - Docker image: `ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0-sha-<sha>`
   - Helm chart: `oci://ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0+sha-<sha>`

## 📋 Workflow Summary

### On PR Creation

```
PR Created
  ↓
CI Workflow Triggers
  ↓
┌─────────────────────────────────┐
│ test: Unit tests, linting      │
│ docker-build: Build image      │
│ helm: Package chart             │
│ build: Build binary             │
│ e2e: Test with built artifacts │
│ kubesec: Security scan         │
└─────────────────────────────────┘
  ↓
Codecov: Upload coverage, comment on PR
  ↓
All checks pass → Ready to merge
```

### On Merge to Master

```
Merge to Master
  ↓
CD Workflow Triggers
  ↓
┌──────────────────────────────────────┐
│ build-and-push:                     │
│   - Build Docker image              │
│   - Sign image (cosign)             │
│   - Push image to GHCR              │
│   - Package Helm chart               │
│   - Push chart to GHCR               │
└──────────────────────────────────────┘
  ↓
┌──────────────────────────────────────┐
│ e2e:                                 │
│   - Pull image from GHCR             │
│   - Pull chart from GHCR             │
│   - Run e2e tests                    │
└──────────────────────────────────────┘
  ↓
Production artifacts verified ✅
```

## 🎯 Key Features

1. **Immutable Versioning**
   - Docker images: `0.1.0-sha-abc1234`
   - Helm charts: `0.1.0+sha-abc1234`
   - Prevents overwrites, ensures traceability

2. **Image Signing**
   - All production images signed with cosign
   - Keyless signing using GitHub OIDC
   - Provides authenticity and integrity

3. **E2E Testing**
   - Tests run on PRs with built artifacts
   - Tests run on master with production artifacts
   - Validates complete deployment workflow

4. **Code Coverage**
   - Tracked in every PR
   - Visible in PR comments
   - Prevents coverage regression

## 📚 Documentation

- **Main Documentation:** [CI/CD Pipeline Documentation](./cicd-pipeline.md)
- **Testing Guide:** [Testing Documentation](./testing.md)
- **Image Signing:** [Image Signing Documentation](./image-signing.md)
- **Helm Deployment:** [Helm Deployment Documentation](./helm-deployment.md)

## 🔧 Troubleshooting

### Codecov Not Showing in PR

**Symptoms:**

- No Codecov comment in PR
- No Codecov status check

**Solutions:**

1. Verify `CODECOV_TOKEN` secret is set
2. Check Codecov repository is enabled
3. Verify `codecov.yml` exists in repo root
4. Check CI workflow uploads coverage file correctly
5. Ensure coverage file path matches: `coverage/unit-coverage.out`

### E2E Tests Fail

**Symptoms:**

- E2E job fails in CI or CD

**Solutions:**

1. Check if kind cluster is created successfully
2. Verify Docker image builds correctly
3. Check Helm chart is packaged correctly
4. Review e2e test logs for specific failures
5. Test locally first: `make e2e-tests`

### CD Doesn't Run on Master

**Symptoms:**

- No CD workflow triggered after merge

**Solutions:**

1. Verify branch is `master` (not `main`)
2. Check workflow file: `.github/workflows/cd.yml`
3. Verify workflow is enabled in Actions tab
4. Check if workflow has syntax errors

## ✅ Final Checklist

Before considering the pipeline complete:

- [ ] `CODECOV_TOKEN` secret is set in GitHub
- [ ] Codecov repository is enabled
- [ ] Test PR created and CI runs successfully
- [ ] Codecov comment appears in test PR
- [ ] Test PR merged to master
- [ ] CD runs successfully on master
- [ ] Artifacts visible in GHCR
- [ ] E2E tests pass with production artifacts
- [ ] Documentation reviewed and accurate

## 🚀 Next Steps

1. **Set up Codecov:**

   ```bash
   # Visit https://codecov.io/gh/deepak-muley/dm-nkp-gitops-custom-app
   # Enable repository and get token
   # Add to GitHub Secrets as CODECOV_TOKEN
   ```

2. **Test the Pipeline:**

   ```bash
   # Create a test PR
   git checkout -b test/ci-pipeline
   git commit --allow-empty -m "test: verify CI/CD pipeline"
   git push origin test/ci-pipeline
   # Create PR and verify all checks pass
   ```

3. **Monitor First Production Run:**
   - Merge test PR to master
   - Watch CD workflow
   - Verify artifacts in GHCR
   - Check e2e tests pass

## 📞 Support

If you encounter issues:

1. Check workflow logs in GitHub Actions
2. Review documentation in `docs/cicd-pipeline.md`
3. Check troubleshooting section above
4. Verify all secrets are configured correctly
