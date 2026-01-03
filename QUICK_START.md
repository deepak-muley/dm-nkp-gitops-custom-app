# Quick Start Verification Guide

Quick reference for verifying the build and CI/CD setup.

## Prerequisites Check

```bash
# Verify all tools are installed
go version          # Should be 1.25+
docker --version    # Docker should be running
make --version      # Make should be available
helm version        # Helm 3.x
pack version        # Pack CLI for buildpacks
kubesec version     # Kubesec for security scanning
```

## Quick Verification Steps

### 1. Local Build (30 seconds)

```bash
make clean && make deps && make build
./bin/dm-nkp-gitops-custom-app &
curl http://localhost:8080/health
pkill dm-nkp-gitops-custom-app
```

### 2. Docker Build - Dockerfile (1 minute)

```bash
docker build -t test-app .
docker run -d --name test -p 8080:8080 test-app
sleep 2 && curl http://localhost:8080/health
docker stop test && docker rm test
```

### 3. Docker Build - Buildpacks (2 minutes)

```bash
make docker-build
docker run -d --name test -p 8080:8080 \
  ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0
sleep 2 && curl http://localhost:8080/health
docker stop test && docker rm test
```

### 4. Helm Chart (30 seconds)

```bash
make helm-chart
helm lint chart/dm-nkp-gitops-custom-app
helm template test chart/dm-nkp-gitops-custom-app | head -20
```

### 5. Security Scan (30 seconds)

```bash
make kubesec
make kubesec-helm
```

### 6. Full CI Simulation (5 minutes)

```bash
make clean
make deps
make lint
make build
make test
make docker-build
make helm-chart
make kubesec
make kubesec-helm
```

## Expected Results

✅ All commands complete without errors  
✅ Binary runs and responds to HTTP requests  
✅ Docker images build successfully  
✅ Helm chart packages correctly  
✅ Security scans show high scores  
✅ All tests pass  

## Troubleshooting

**Build fails?**
```bash
go mod tidy
make clean && make build
```

**Docker build fails?**
```bash
docker system prune -f
docker build --no-cache -t test .
```

**Pack build fails?**
```bash
pack builder suggest
pack build test --clear-cache
```

## Next Steps

See [docs/verification.md](docs/verification.md) for detailed verification steps.

