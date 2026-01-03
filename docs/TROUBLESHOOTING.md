# Troubleshooting Guide

This guide helps you diagnose and resolve common issues with dm-nkp-gitops-custom-app.

## Table of Contents

- [Build Issues](#build-issues)
- [Deployment Issues](#deployment-issues)
- [CI/CD Issues](#cicd-issues)
- [Testing Issues](#testing-issues)
- [Security Issues](#security-issues)
- [Performance Issues](#performance-issues)

## Build Issues

### Issue: `pack build` fails

**Symptoms:**
- Build fails with builder errors
- Cannot find builder image

**Solutions:**
```bash
# Pull the latest builder
pack builder pull gcr.io/buildpacks/builder:google-22

# Verify builder is available
pack builder suggest

# Try building with explicit pull policy
pack build <image> --pull-policy always
```

### Issue: Go module download fails

**Symptoms:**
- `go mod download` fails
- Network timeouts

**Solutions:**
```bash
# Set Go proxy (if behind firewall)
export GOPROXY=https://proxy.golang.org,direct

# Clear module cache
go clean -modcache

# Try again
make deps
```

### Issue: Docker image too large

**Symptoms:**
- Image size exceeds expectations
- Build warnings about size

**Solutions:**
- Use multi-stage builds (if using Dockerfile)
- Ensure buildpacks are using distroless base images
- Check for unnecessary files in image
- Review `.dockerignore` (if using Dockerfile)

## Deployment Issues

### Issue: Pod fails to start

**Symptoms:**
- Pod in `CrashLoopBackOff` state
- Container exits immediately

**Solutions:**
```bash
# Check pod logs
kubectl logs <pod-name> -n <namespace>

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check container status
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.status.containerStatuses}'
```

**Common Causes:**
- Missing environment variables
- Incorrect image pull secrets
- Resource constraints
- Security context issues

### Issue: Image pull fails

**Symptoms:**
- `ErrImagePull` or `ImagePullBackOff`
- Authentication errors

**Solutions:**
```bash
# Verify image exists
docker pull ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:<version>

# Check image pull secrets
kubectl get secret <secret-name> -n <namespace>

# Create image pull secret
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<username> \
  --docker-password=<token> \
  --docker-email=<email> \
  -n <namespace>
```

### Issue: Health checks failing

**Symptoms:**
- Pod restarts frequently
- Readiness probe failures

**Solutions:**
```bash
# Test health endpoint manually
kubectl port-forward <pod-name> 8080:8080 -n <namespace>
curl http://localhost:8080/health
curl http://localhost:8080/ready

# Check probe configuration
kubectl get deployment <deployment-name> -n <namespace> -o yaml | grep -A 10 probes
```

## CI/CD Issues

### Issue: CI workflow fails

**Symptoms:**
- GitHub Actions workflow fails
- Tests fail in CI but pass locally

**Solutions:**
1. **Check workflow logs:**
   - Go to Actions tab
   - Click on failed workflow run
   - Review logs for specific step

2. **Common causes:**
   - Missing secrets (CODECOV_TOKEN, etc.)
   - Go version mismatch
   - Network issues
   - Timeout issues

3. **Debug locally:**
   ```bash
   # Run same commands as CI
   make deps
   make lint
   make test
   make docker-build
   ```

### Issue: CD workflow doesn't trigger

**Symptoms:**
- CD workflow doesn't run on master push
- No artifacts pushed to registry

**Solutions:**
- Verify workflow file exists: `.github/workflows/cd.yml`
- Check workflow conditions: `if: github.ref == 'refs/heads/master'`
- Verify branch name is exactly `master`
- Check workflow permissions in repository settings

### Issue: Artifacts not pushed

**Symptoms:**
- Build succeeds but artifacts not in registry
- Authentication errors

**Solutions:**
```bash
# Verify GITHUB_TOKEN has write:packages permission
# Check workflow permissions
# Verify registry path is correct
```

## Testing Issues

### Issue: Unit tests fail

**Symptoms:**
- Tests fail locally or in CI
- Coverage below threshold

**Solutions:**
```bash
# Run tests with verbose output
go test -v ./internal/...

# Run specific test
go test -v -run TestName ./internal/package/...

# Check coverage
go test -coverprofile=coverage.out ./internal/...
go tool cover -html=coverage.out
```

### Issue: E2E tests fail

**Symptoms:**
- E2E tests fail in kind cluster
- Timeout errors

**Solutions:**
```bash
# Verify kind cluster is running
kind get clusters

# Check cluster status
kubectl cluster-info --context kind-<cluster-name>

# Increase test timeout
go test -v -tags=e2e -timeout=30m ./tests/e2e/...

# Check pod logs
kubectl logs -l app=dm-nkp-gitops-custom-app -n <namespace>
```

### Issue: Integration tests fail

**Symptoms:**
- Integration tests fail
- Server doesn't start

**Solutions:**
```bash
# Run with integration tag
go test -v -tags=integration ./tests/integration/...

# Check if ports are available
lsof -i :8080
lsof -i :9090

# Run with race detector
go test -race -tags=integration ./tests/integration/...
```

## Security Issues

### Issue: Security scans fail

**Symptoms:**
- CodeQL or Trivy finds vulnerabilities
- Security workflow fails

**Solutions:**
1. **Review findings:**
   - Go to Security tab
   - Review CodeQL alerts
   - Review dependency alerts

2. **Fix vulnerabilities:**
   ```bash
   # Update dependencies
   go get -u ./...
   go mod tidy

   # Review Trivy findings
   trivy image <image-name>
   ```

3. **Suppress false positives:**
   - Add to `.github/codeql/codeql-config.yml` for CodeQL
   - Document in security workflow for Trivy

### Issue: Secret scanning finds secrets

**Symptoms:**
- Secret scanning alerts
- Pre-commit hook fails

**Solutions:**
```bash
# Remove secrets from git history (if committed)
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch <file>" \
  --prune-empty --tag-name-filter cat -- --all

# Rotate compromised secrets
# Add to .gitignore
# Update .secrets.baseline
```

## Performance Issues

### Issue: Slow builds

**Symptoms:**
- Docker builds take too long
- CI runs are slow

**Solutions:**
- Use build cache
- Optimize Dockerfile/buildpack configuration
- Use parallel builds where possible
- Review CI workflow for optimization opportunities

### Issue: High memory usage

**Symptoms:**
- Pods OOMKilled
- High memory consumption

**Solutions:**
```bash
# Check memory usage
kubectl top pod <pod-name> -n <namespace>

# Review resource limits
kubectl get deployment <deployment-name> -n <namespace> -o yaml | grep -A 5 resources

# Adjust resource requests/limits in values.yaml
```

## Getting Help

If you're still experiencing issues:

1. **Check Documentation:**
   - [README.md](../README.md)
   - [docs/development.md](development.md)
   - [docs/deployment.md](deployment.md)

2. **Search Issues:**
   - Search existing GitHub issues
   - Check closed issues for similar problems

3. **Create an Issue:**
   - Use the bug report template
   - Include logs and error messages
   - Describe steps to reproduce

4. **Community:**
   - Check CONTRIBUTING.md for contribution guidelines
   - Review CODE_OF_CONDUCT.md

## Common Commands

```bash
# Build and test locally
make deps
make lint
make test
make docker-build

# Deploy to Kubernetes
helm install my-app chart/dm-nkp-gitops-custom-app

# Check deployment
kubectl get pods -l app=dm-nkp-gitops-custom-app
kubectl logs -l app=dm-nkp-gitops-custom-app

# Run e2e tests
make e2e-tests

# Check security
make check-secrets
make kubesec
```

## Additional Resources

- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug/)
- [Docker Troubleshooting](https://docs.docker.com/config/daemon/)
- [GitHub Actions Troubleshooting](https://docs.github.com/en/actions/guides/debugging-workflows)
- [Go Troubleshooting](https://golang.org/doc/faq)

