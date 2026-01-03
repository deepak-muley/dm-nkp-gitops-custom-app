.PHONY: help build test unit-tests integration-tests e2e-tests clean lint fmt vet deps helm-chart push-helm-chart helm-chart-digest docker-build docker-push docker-sign docker-verify check-artifact check-secrets setup-branch-protection check-branch-protection check-branch-protection-repo kubesec kubesec-helm

# Variables
APP_NAME := dm-nkp-gitops-custom-app
VERSION := 0.1.0
REGISTRY := ghcr.io/deepak-muley/dm-nkp-gitops-custom-app
HELM_CHART_NAME := $(APP_NAME)
HELM_REPO := oci://$(REGISTRY)
GO_VERSION := 1.25
BUILD_DIR := bin
COVERAGE_DIR := coverage
# Set PUBLIC=true to make the Helm chart public after pushing (default: false)
PUBLIC ?= false
# Set IMMUTABLE=true to use Git SHA in version for immutable versioning (default: true)
IMMUTABLE ?= true
# Set SIGN=true to sign container images with cosign (default: false)
SIGN ?= false

# Generate immutable version with Git SHA if IMMUTABLE=true, otherwise use base VERSION
# Note: Docker image tags cannot contain '+', so we use '-' for images and '+' for Helm charts
GIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_SHA_FULL := $(shell git rev-parse HEAD 2>/dev/null || echo "unknown")
ifeq ($(IMMUTABLE),true)
  # Docker images: use '-' (e.g., 0.1.0-sha-abc1234)
  IMAGE_VERSION := $(VERSION)-sha-$(GIT_SHA)
  # Helm charts: use '+' (OCI supports it, e.g., 0.1.0+sha-abc1234)
  HELM_CHART_VERSION := $(VERSION)+sha-$(GIT_SHA)
else
  IMAGE_VERSION := $(VERSION)
  HELM_CHART_VERSION := $(VERSION)
endif
IMAGE := $(REGISTRY)/$(APP_NAME):$(IMAGE_VERSION)

# Go parameters
GOCMD := go
GOBUILD := $(GOCMD) build
GOTEST := $(GOCMD) test
GOMOD := $(GOCMD) mod
GOFMT := $(GOCMD) fmt
GOVET := $(GOCMD) vet

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deps: ## Download dependencies
	$(GOMOD) download
	$(GOMOD) tidy

fmt: ## Format code
	$(GOFMT) ./...

vet: ## Run go vet
	$(GOVET) ./...

lint: fmt vet ## Run linters

build: ## Build the application
	@mkdir -p $(BUILD_DIR)
	$(GOBUILD) -o $(BUILD_DIR)/$(APP_NAME) -v ./cmd/app

test: unit-tests ## Run all tests

unit-tests: ## Run unit tests with coverage check (requires 100% coverage)
	@mkdir -p $(COVERAGE_DIR)
	$(GOTEST) -v -race -coverprofile=$(COVERAGE_DIR)/unit-coverage.out -covermode=atomic ./internal/...
	@echo ""
	@echo "Unit test coverage:"
	@$(GOCMD) tool cover -func=$(COVERAGE_DIR)/unit-coverage.out | tail -1
	@echo ""
	@echo "Checking for 100% coverage..."
	@COVERAGE_OUTPUT=$$($(GOCMD) tool cover -func=$(COVERAGE_DIR)/unit-coverage.out | tail -1); \
	COVERAGE_PCT=$$(echo "$$COVERAGE_OUTPUT" | awk '{print $$3}' | sed 's/%//'); \
	if [ -z "$$COVERAGE_PCT" ]; then \
		echo "Error: Could not parse coverage percentage"; \
		exit 1; \
	fi; \
	COVERAGE_INT=$$(echo "$$COVERAGE_PCT" | awk -F. '{print $$1}'); \
	if [ "$$COVERAGE_INT" -lt 100 ]; then \
		echo "Error: Coverage is $$COVERAGE_PCT%, expected 100%"; \
		echo "Functions not fully covered:"; \
		$(GOCMD) tool cover -func=$(COVERAGE_DIR)/unit-coverage.out | grep "github.com/deepak-muley" | grep -v "100.0%"; \
		exit 1; \
	fi
	@echo "✓ Coverage is 100%"

integration-tests: ## Run integration tests
	$(GOTEST) -v -tags=integration -race ./tests/integration/...

e2e-tests: ## Run e2e tests
	@if ! command -v kind > /dev/null; then \
		echo "kind is not installed. Install it from https://kind.sigs.k8s.io/"; \
		exit 1; \
	fi
	@if ! command -v curl > /dev/null; then \
		echo "curl is not installed"; \
		exit 1; \
	fi
	$(GOTEST) -v -tags=e2e -timeout=30m ./tests/e2e/...

clean: ## Clean build artifacts
	rm -rf $(BUILD_DIR)
	rm -rf $(COVERAGE_DIR)
	$(GOCMD) clean -cache

helm-chart: ## Package Helm chart (use IMMUTABLE=false to disable Git SHA in version)
	@if ! command -v helm > /dev/null; then \
		echo "helm is not installed. Install it from https://helm.sh/"; \
		exit 1; \
	fi
	@echo "Packaging Helm chart with version: $(HELM_CHART_VERSION)"
	helm package chart/$(APP_NAME) --version $(HELM_CHART_VERSION) --app-version $(VERSION) -d chart/
	@echo "Helm chart packaged: chart/$(APP_NAME)-$(HELM_CHART_VERSION).tgz"

push-helm-chart: helm-chart ## Push Helm chart to OCI registry (use PUBLIC=true to make it public, IMMUTABLE=false to disable Git SHA)
	@if ! command -v helm > /dev/null; then \
		echo "helm is not installed. Install it from https://helm.sh/"; \
		exit 1; \
	fi
	@bash -c '\
		if [ -f .env.local ]; then \
			. .env.local; \
		fi; \
		if [ -z "$$GITHUB_TOKEN" ]; then \
			echo "GITHUB_TOKEN environment variable is not set"; \
			echo "Create a GitHub Personal Access Token (PAT) with '\''write:packages'\'' permission"; \
			echo "Then either:"; \
			echo "  1. Create .env.local file with: export GITHUB_TOKEN=your_token_here"; \
			echo "  2. Or run: export GITHUB_TOKEN=your_token_here"; \
			exit 1; \
		fi; \
		echo "Logging in to GHCR..."; \
		echo $$GITHUB_TOKEN | helm registry login ghcr.io -u $(shell git config user.name) --password-stdin; \
		echo "Pushing Helm chart $(HELM_CHART_VERSION) to $(HELM_REPO)..."; \
		helm push chart/$(APP_NAME)-$(HELM_CHART_VERSION).tgz $(HELM_REPO); \
		echo "✓ Helm chart pushed to $(HELM_REPO)"; \
		echo ""; \
		echo "Chart reference:"; \
		echo "  Tag: $(HELM_REPO)/$(HELM_CHART_NAME):$(HELM_CHART_VERSION)"; \
		if [ "$(IMMUTABLE)" = "true" ]; then \
			echo "  Git SHA: $(GIT_SHA_FULL)"; \
			echo ""; \
			echo "To get the immutable digest, run:"; \
			echo "  make helm-chart-digest VERSION=$(HELM_CHART_VERSION)"; \
		fi; \
		if [ "$(PUBLIC)" = "true" ] || [ "$(PUBLIC)" = "1" ]; then \
			echo "Making Helm chart public..."; \
			PACKAGE_NAME="$(HELM_CHART_NAME)"; \
			if command -v gh > /dev/null; then \
				echo "Using GitHub CLI to make chart public..."; \
				export GITHUB_TOKEN; \
				if gh api -X PATCH /user/packages/container/$$PACKAGE_NAME -f visibility=public > /dev/null 2>&1; then \
					echo "✓ Helm chart is now public"; \
				else \
					echo "Warning: Failed to make chart public using GitHub CLI"; \
					echo "You may need to make it public manually via GitHub web interface"; \
				fi; \
			elif command -v curl > /dev/null; then \
				echo "Using curl to make chart public..."; \
				API_RESPONSE=$$(curl -s -w "\n%{http_code}" -X PATCH \
					-H "Accept: application/vnd.github+json" \
					-H "Authorization: Bearer $$GITHUB_TOKEN" \
					-H "X-GitHub-Api-Version: 2022-11-28" \
					https://api.github.com/user/packages/container/$$PACKAGE_NAME \
					-d "{\"visibility\":\"public\"}"); \
				HTTP_CODE=$$(echo "$$API_RESPONSE" | tail -n1); \
				if [ "$$HTTP_CODE" = "204" ] || [ "$$HTTP_CODE" = "200" ]; then \
					echo "✓ Helm chart is now public"; \
				else \
					echo "Warning: Failed to make chart public (HTTP $$HTTP_CODE)"; \
					echo "Response: $$(echo "$$API_RESPONSE" | head -n-1)"; \
					echo "You may need to make it public manually via GitHub web interface"; \
				fi; \
			else \
				echo "Warning: Neither 'gh' (GitHub CLI) nor 'curl' is installed."; \
				echo "Cannot make chart public automatically."; \
				echo "Install one of them or make the package public manually via GitHub web interface:"; \
				echo "  https://github.com/users/$(shell git config user.name)/packages/container/package/$$PACKAGE_NAME"; \
			fi; \
		fi'

helm-chart-digest: ## Get the immutable digest for a Helm chart version (use CHART_VERSION=0.1.0+sha-abc123)
	@bash -c '\
		if [ -f .env.local ]; then \
			. .env.local; \
		fi; \
		if [ -z "$$GITHUB_TOKEN" ]; then \
			echo "GITHUB_TOKEN environment variable is not set"; \
			exit 1; \
		fi; \
		if [ -n "$(CHART_VERSION)" ]; then \
			CHART_VERSION="$(CHART_VERSION)"; \
		elif [ "$(IMMUTABLE)" = "true" ]; then \
			CHART_VERSION="$(HELM_CHART_VERSION)"; \
		else \
			CHART_VERSION="$(VERSION)"; \
		fi; \
		echo "Fetching digest for chart version: $$CHART_VERSION"; \
		echo $$GITHUB_TOKEN | helm registry login ghcr.io -u $(shell git config user.name) --password-stdin > /dev/null 2>&1; \
		CHART_REF="$(HELM_REPO)/$(HELM_CHART_NAME):$$CHART_VERSION"; \
		if command -v crane > /dev/null; then \
			DIGEST=$$(crane digest $$CHART_REF 2>/dev/null); \
			if [ -n "$$DIGEST" ]; then \
				echo ""; \
				echo "Chart digest:"; \
				echo "  $$DIGEST"; \
				echo ""; \
				echo "Immutable reference:"; \
				echo "  $(HELM_REPO)/$(HELM_CHART_NAME)@$$DIGEST"; \
				echo ""; \
				echo "Use this reference in your deployments for immutability:"; \
				echo "  helm install my-app $(HELM_REPO)/$(HELM_CHART_NAME) --version $$CHART_VERSION --oci-registry-config ~/.docker/config.json"; \
				echo "  # Or with digest:"; \
				echo "  helm install my-app $(HELM_REPO)/$(HELM_CHART_NAME)@$$DIGEST --oci-registry-config ~/.docker/config.json"; \
			else \
				echo "Error: Could not retrieve digest. Chart may not exist or version may be incorrect."; \
				exit 1; \
			fi; \
		elif command -v skopeo > /dev/null; then \
			MANIFEST=$$(skopeo inspect --creds $(shell git config user.name):$$GITHUB_TOKEN docker://$$CHART_REF 2>/dev/null); \
			if [ -n "$$MANIFEST" ]; then \
				DIGEST=$$(echo "$$MANIFEST" | grep -o '"sha256:[a-f0-9]*"' | head -1 | tr -d \"); \
				if [ -n "$$DIGEST" ]; then \
					echo ""; \
					echo "Chart digest:"; \
					echo "  $$DIGEST"; \
					echo ""; \
					echo "Immutable reference:"; \
					echo "  $(HELM_REPO)/$(HELM_CHART_NAME)@$$DIGEST"; \
				else \
					echo "Error: Could not extract digest from manifest."; \
					exit 1; \
				fi; \
			else \
				echo "Error: Could not retrieve manifest. Chart may not exist or version may be incorrect."; \
				exit 1; \
			fi; \
		else \
			echo "Error: Neither 'crane' nor 'skopeo' is installed."; \
			echo "Install one of them to retrieve chart digests:"; \
			echo "  - crane: https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md"; \
			echo "  - skopeo: https://github.com/containers/skopeo"; \
			echo ""; \
			echo "Alternatively, use helm show to get chart information:"; \
			echo "  helm show chart $(HELM_REPO)/$(HELM_CHART_NAME) --version $$CHART_VERSION"; \
			exit 1; \
		fi'

check-secrets: ## Check for accidentally committed secrets or private keys
	@./scripts/check-secrets.sh

setup-branch-protection: ## Set up branch protection for master branch (requires GitHub CLI)
	@./scripts/branch-protect.sh --setup

check-branch-protection: ## Check branch protection status (read-only, shows what --setup would do)
	@./scripts/branch-protect.sh --show

check-branch-protection-repo: ## Check branch protection for another repo (use REPO=owner/repo BRANCH=branch)
	@if [ -z "$(REPO)" ]; then \
		echo "Error: REPO variable is required"; \
		echo "Usage: make check-branch-protection-repo REPO=owner/repo [BRANCH=branch]"; \
		echo "Example: make check-branch-protection-repo REPO=kubernetes/kubernetes BRANCH=main"; \
		exit 1; \
	fi
	@if [ -n "$(BRANCH)" ]; then \
		./scripts/branch-protect.sh --show $(REPO) --branch $(BRANCH); \
	else \
		./scripts/branch-protect.sh --show $(REPO); \
	fi

check-artifact: ## Check if an artifact is a Docker image or Helm chart (use ARTIFACT=ghcr.io/user/package:tag)
	@bash -c '\
		if [ -z "$(ARTIFACT)" ]; then \
			echo "Error: ARTIFACT variable is required"; \
			echo "Usage: make check-artifact ARTIFACT=ghcr.io/user/package:tag"; \
			echo ""; \
			echo "Examples:"; \
			echo "  make check-artifact ARTIFACT=ghcr.io/deepak-muley/dm-nkp-gitops-custom-app/dm-nkp-gitops-custom-app:0.1.0+sha-abc1234"; \
			exit 1; \
		fi; \
		if [ -f .env.local ]; then \
			. .env.local; \
		fi; \
		if ! command -v crane > /dev/null && ! command -v skopeo > /dev/null; then \
			echo "Error: Neither 'crane' nor 'skopeo' is installed"; \
			echo "Install one of them to check artifact types:"; \
			echo "  - crane: brew install crane"; \
			echo "  - skopeo: brew install skopeo"; \
			exit 1; \
		fi; \
		echo "Checking artifact: $(ARTIFACT)"; \
		echo ""; \
		if command -v crane > /dev/null; then \
			MANIFEST=$$(crane manifest $(ARTIFACT) 2>/dev/null); \
			if [ -z "$$MANIFEST" ]; then \
				echo "Error: Could not retrieve manifest. Artifact may not exist or authentication failed."; \
				exit 1; \
			fi; \
			MEDIA_TYPE=$$(echo "$$MANIFEST" | jq -r ".mediaType // .config.mediaType // empty" 2>/dev/null); \
			HAS_HELM_ANNOTATIONS=$$(echo "$$MANIFEST" | jq -e '.annotations."org.opencontainers.image.title"' > /dev/null 2>&1 && echo "yes" || echo "no"); \
			HAS_DOCKER_CONFIG=$$(echo "$$MANIFEST" | jq -e '.config' > /dev/null 2>&1 && echo "yes" || echo "no"); \
			echo "Media Type: $$MEDIA_TYPE"; \
			echo ""; \
			if [ "$$HAS_HELM_ANNOTATIONS" = "yes" ]; then \
				echo "✓ This is a HELM CHART"; \
				CHART_NAME=$$(echo "$$MANIFEST" | jq -r '.annotations."org.opencontainers.image.title" // "unknown"'); \
				CHART_VERSION=$$(echo "$$MANIFEST" | jq -r '.annotations."org.opencontainers.image.version" // "unknown"'); \
				echo "  Chart Name: $$CHART_NAME"; \
				echo "  Chart Version: $$CHART_VERSION"; \
				echo ""; \
				echo "Use with Helm:"; \
				echo "  helm pull oci://$(ARTIFACT%:*) --version $(ARTIFACT##*:)"; \
				echo "  helm install my-app oci://$(ARTIFACT%:*) --version $(ARTIFACT##*:)"; \
			elif [ "$$HAS_DOCKER_CONFIG" = "yes" ] || echo "$$MEDIA_TYPE" | grep -q "docker"; then \
				echo "✓ This is a DOCKER IMAGE"; \
				echo ""; \
				echo "Use with Docker:"; \
				echo "  docker pull $(ARTIFACT)"; \
				echo "  docker run $(ARTIFACT)"; \
			else \
				echo "? Unknown artifact type"; \
				echo "  Media Type: $$MEDIA_TYPE"; \
			fi; \
		elif command -v skopeo > /dev/null; then \
			if [ -n "$$GITHUB_TOKEN" ]; then \
				MANIFEST=$$(skopeo inspect --creds $(shell git config user.name):$$GITHUB_TOKEN docker://$(ARTIFACT) 2>/dev/null); \
			else \
				MANIFEST=$$(skopeo inspect docker://$(ARTIFACT) 2>/dev/null); \
			fi; \
			if [ -z "$$MANIFEST" ]; then \
				echo "Error: Could not retrieve manifest"; \
				exit 1; \
			fi; \
			MEDIA_TYPE=$$(echo "$$MANIFEST" | jq -r ".MediaType // empty"); \
			echo "Media Type: $$MEDIA_TYPE"; \
			echo ""; \
			if echo "$$MEDIA_TYPE" | grep -q "helm\|chart"; then \
				echo "✓ This is a HELM CHART"; \
			elif echo "$$MEDIA_TYPE" | grep -q "docker\|container"; then \
				echo "✓ This is a DOCKER IMAGE"; \
			else \
				echo "? Unknown artifact type"; \
			fi; \
		fi'

docker-build: ## Build Docker image using buildpacks (use IMMUTABLE=false to disable Git SHA in version)
	@if ! command -v pack > /dev/null; then \
		echo "pack is not installed. Install it from https://buildpacks.io/docs/tools/pack/"; \
		exit 1; \
	fi
	@echo "Building Docker image with version: $(IMAGE_VERSION)"
	pack build $(IMAGE) \
		--builder gcr.io/buildpacks/builder:google-22 \
		--env GOOGLE_RUNTIME_VERSION=$(GO_VERSION) \
		--env GOOGLE_BUILDABLE=./cmd/app \
		--env PORT=8080 \
		--env METRICS_PORT=9090
	@echo "✓ Docker image built: $(IMAGE)"

docker-push: docker-build ## Build and push Docker image (use SIGN=true to sign with cosign)
	@bash -c '\
		if [ -f .env.local ]; then \
			. .env.local; \
		fi; \
		if [ -z "$$GITHUB_TOKEN" ]; then \
			echo "GITHUB_TOKEN environment variable is not set"; \
			echo "Create a GitHub Personal Access Token (PAT) with '\''write:packages'\'' permission"; \
			echo "Then either:"; \
			echo "  1. Create .env.local file with: export GITHUB_TOKEN=your_token_here"; \
			echo "  2. Or run: export GITHUB_TOKEN=your_token_here"; \
			exit 1; \
		fi; \
		echo "Logging in to GHCR..."; \
		docker login ghcr.io -u $(shell git config user.name) -p $$GITHUB_TOKEN; \
		echo "Pushing Docker image $(IMAGE)..."; \
		docker push $(IMAGE); \
		echo "✓ Docker image pushed to $(IMAGE)"; \
		if [ "$(IMMUTABLE)" = "true" ]; then \
			echo "  Git SHA: $(GIT_SHA_FULL)"; \
		fi; \
		if [ "$(SIGN)" = "true" ] || [ "$(SIGN)" = "1" ]; then \
			echo ""; \
			echo "Signing Docker image..."; \
			$(MAKE) docker-sign IMAGE=$(IMAGE); \
		fi'

docker-sign: ## Sign Docker image with cosign (requires COSIGN_PASSWORD or keyless signing)
	@bash -c '\
		if [ -f .env.local ]; then \
			. .env.local; \
		fi; \
		if [ -z "$(IMAGE)" ]; then \
			echo "Error: IMAGE variable is required"; \
			echo "Usage: make docker-sign IMAGE=ghcr.io/user/image:tag"; \
			exit 1; \
		fi; \
		if ! command -v cosign > /dev/null; then \
			echo "Error: cosign is not installed"; \
			echo "Install it from: https://github.com/sigstore/cosign"; \
			echo "  brew install cosign"; \
			echo "  or download from: https://github.com/sigstore/cosign/releases"; \
			exit 1; \
		fi; \
		echo "Signing image: $(IMAGE)"; \
		if [ -n "$$COSIGN_PASSWORD" ] && [ -n "$$COSIGN_KEY_PATH" ]; then \
			echo "Using key-based signing..."; \
			COSIGN_PASSWORD=$$COSIGN_PASSWORD cosign sign --key $$COSIGN_KEY_PATH $(IMAGE); \
		elif [ -n "$$COSIGN_EXPERIMENTAL" ] && [ "$$COSIGN_EXPERIMENTAL" = "1" ]; then \
			echo "Using keyless signing (experimental)..."; \
			COSIGN_EXPERIMENTAL=1 cosign sign $(IMAGE); \
		else \
			echo "Using keyless signing with GitHub OIDC..."; \
			if [ -n "$$GITHUB_TOKEN" ]; then \
				export COSIGN_EXPERIMENTAL=1; \
				cosign sign $(IMAGE); \
			else \
				echo "Error: GITHUB_TOKEN is required for keyless signing"; \
				echo "Or set COSIGN_PASSWORD and COSIGN_KEY_PATH for key-based signing"; \
				exit 1; \
			fi; \
		fi; \
		echo "✓ Image signed successfully"; \
		echo ""; \
		echo "To verify the signature, run:"; \
		echo "  make docker-verify IMAGE=$(IMAGE)"'

docker-verify: ## Verify Docker image signature with cosign
	@bash -c '\
		if [ -z "$(IMAGE)" ]; then \
			echo "Error: IMAGE variable is required"; \
			echo "Usage: make docker-verify IMAGE=ghcr.io/user/image:tag"; \
			exit 1; \
		fi; \
		if ! command -v cosign > /dev/null; then \
			echo "Error: cosign is not installed"; \
			echo "Install it from: https://github.com/sigstore/cosign"; \
			exit 1; \
		fi; \
		echo "Verifying signature for: $(IMAGE)"; \
		if [ -n "$$COSIGN_KEY_PATH" ]; then \
			cosign verify --key $$COSIGN_KEY_PATH $(IMAGE); \
		else \
			cosign verify $(IMAGE); \
		fi; \
		if [ $$? -eq 0 ]; then \
			echo "✓ Image signature verified successfully"; \
		else \
			echo "✗ Image signature verification failed"; \
			exit 1; \
		fi'

kubesec: ## Run kubesec security scan on base manifests
	@if ! command -v kubesec > /dev/null; then \
		echo "kubesec is not installed. Install it from https://github.com/controlplaneio/kubesec"; \
		echo "  brew install kubesec"; \
		exit 1; \
	fi
	@echo "Running kubesec scan on base manifests..."
	@kubesec scan manifests/base/deployment.yaml || true
	@kubesec scan manifests/base/service.yaml || true

kubesec-helm: helm-chart ## Run kubesec security scan on rendered Helm chart
	@if ! command -v kubesec > /dev/null; then \
		echo "kubesec is not installed. Install it from https://github.com/controlplaneio/kubesec"; \
		echo "  brew install kubesec"; \
		exit 1; \
	fi
	@if ! command -v helm > /dev/null; then \
		echo "helm is not installed. Install it from https://helm.sh/"; \
		exit 1; \
	fi
	@echo "Rendering Helm chart and running kubesec scan..."
	@helm template chart/$(APP_NAME) | kubesec scan - || true

setup-monitoring-helm: ## Set up monitoring stack (Prometheus + Grafana) using Helm charts
	@if ! command -v helm > /dev/null; then \
		echo "helm is not installed. Install it from https://helm.sh/"; \
		exit 1; \
	fi
	@if ! command -v kubectl > /dev/null; then \
		echo "kubectl is not installed"; \
		exit 1; \
	fi
	./scripts/setup-monitoring-helm.sh

setup-traefik-helm: ## Set up Traefik using Helm chart
	@if ! command -v helm > /dev/null; then \
		echo "helm is not installed. Install it from https://helm.sh/"; \
		exit 1; \
	fi
	@if ! command -v kubectl > /dev/null; then \
		echo "kubectl is not installed"; \
		exit 1; \
	fi
	./scripts/setup-traefik-helm.sh

setup-gateway-api-helm: ## Set up Gateway API with Traefik using Helm
	@if ! command -v helm > /dev/null; then \
		echo "helm is not installed. Install it from https://helm.sh/"; \
		exit 1; \
	fi
	@if ! command -v kubectl > /dev/null; then \
		echo "kubectl is not installed"; \
		exit 1; \
	fi
	./scripts/setup-gateway-api-helm.sh

all: clean deps lint build test ## Run all: clean, deps, lint, build, test

