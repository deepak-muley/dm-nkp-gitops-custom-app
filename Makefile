.PHONY: help build test unit-tests integration-tests e2e-tests clean lint fmt vet deps helm-chart push-helm-chart helm-chart-digest helm-show-values docker-build docker-push docker-sign docker-verify check-artifact check-secrets setup-branch-protection check-branch-protection check-branch-protection-repo kubesec kubesec-helm setup-pre-commit pre-commit pre-commit-update

# Variables
APP_NAME := dm-nkp-gitops-custom-app
VERSION := 0.1.0
GO_VERSION := 1.25.5
BUILD_DIR := bin
COVERAGE_DIR := coverage
# Set PUBLIC=true to make the Helm chart public after pushing (default: false)
PUBLIC ?= false
# Set IMMUTABLE=true to use Git SHA in version for immutable versioning (default: true)
IMMUTABLE ?= true
# Set SIGN=true to sign container images with cosign (default: false)
SIGN ?= false
# Set REGISTRY_ENV=dev for development, prod for production (default: auto-detect from branch)
# Auto-detects based on current branch: uses 'dev' for non-master branches, 'prod' for master
REGISTRY_ENV ?= $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null | grep -qE '^(master|main)$$' && echo "prod" || echo "dev")
# Base registry path (owner/repo)
REGISTRY_BASE := ghcr.io/deepak-muley/dm-nkp-gitops-custom-app
# Separate package names for clarity: images and charts use different package names
# Container image package name (explicit - no suffix needed)
IMAGE_PACKAGE := $(APP_NAME)
# Helm chart package name (explicit -chart suffix to distinguish from images)
HELM_CHART_PACKAGE := $(APP_NAME)-chart
# Full registry paths with environment prefix and explicit package names
# Format: ghcr.io/owner/repo/{dev|prod}/{package-name}
IMAGE_REGISTRY := $(REGISTRY_BASE)/$(REGISTRY_ENV)/$(IMAGE_PACKAGE)
# Helm automatically appends chart name from Chart.yaml to OCI registry path
# So the actual path will be: {HELM_CHART_REGISTRY}/{CHART_NAME}
HELM_CHART_REGISTRY := $(REGISTRY_BASE)/$(REGISTRY_ENV)/$(HELM_CHART_PACKAGE)
HELM_CHART_NAME := $(APP_NAME)
# Full Helm chart path includes the chart name (Helm appends it automatically)
HELM_CHART_FULL_PATH := $(HELM_CHART_REGISTRY)/$(HELM_CHART_NAME)
HELM_REPO := oci://$(HELM_CHART_REGISTRY)

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
IMAGE := $(IMAGE_REGISTRY):$(IMAGE_VERSION)

# Go parameters
GOCMD := go
GOBUILD := $(GOCMD) build
GOTEST := $(GOCMD) test
GOMOD := $(GOCMD) mod
GOFMT := $(GOCMD) fmt
GOVET := $(GOCMD) vet

# Check if Go files have changed (compared to HEAD or specified base)
# Usage: make check-go-changes [GIT_BASE=origin/main]
# Returns empty string if no changes, or list of changed files if changes exist
check-go-changes:
	@bash -c '\
		if [ -n "$(GIT_BASE)" ]; then \
			BASE="$(GIT_BASE)"; \
		else \
			BASE="HEAD"; \
		fi; \
		CHANGED_FILES=$$(git diff --name-only --diff-filter=ACMRTUXB $$BASE -- "*.go" 2>/dev/null || echo ""); \
		if [ -z "$$CHANGED_FILES" ]; then \
			# Also check working directory for untracked Go files \
			UNTRACKED=$$(git ls-files --others --exclude-standard "*.go" 2>/dev/null || echo ""); \
			if [ -z "$$UNTRACKED" ]; then \
				echo ""; \
				exit 0; \
			else \
				echo "$$UNTRACKED"; \
				exit 0; \
			fi; \
		else \
			echo "$$CHANGED_FILES"; \
			exit 0; \
		fi'

# Check if Go files have changed and exit with code 1 if no changes
# This can be used as a dependency check
has-go-changes:
	@bash -c '\
		if [ -n "$(GIT_BASE)" ]; then \
			BASE="$(GIT_BASE)"; \
		else \
			BASE="HEAD"; \
		fi; \
		CHANGED_FILES=$$(git diff --name-only --diff-filter=ACMRTUXB $$BASE -- "*.go" 2>/dev/null || echo ""); \
		if [ -z "$$CHANGED_FILES" ]; then \
			UNTRACKED=$$(git ls-files --others --exclude-standard "*.go" 2>/dev/null || echo ""); \
			if [ -z "$$UNTRACKED" ]; then \
				echo "No Go files changed. Skipping build/test."; \
				exit 1; \
			fi; \
		fi; \
		exit 0'

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

build: ## Build the application (only if Go files changed)
	@bash -c '\
		if [ -n "$(GIT_BASE)" ]; then \
			BASE="$(GIT_BASE)"; \
		else \
			BASE="HEAD"; \
		fi; \
		CHANGED_FILES=$$(git diff --name-only --diff-filter=ACMRTUXB $$BASE -- "*.go" 2>/dev/null || echo ""); \
		if [ -z "$$CHANGED_FILES" ]; then \
			UNTRACKED=$$(git ls-files --others --exclude-standard "*.go" 2>/dev/null || echo ""); \
			if [ -z "$$UNTRACKED" ]; then \
				echo "No Go files changed since $$BASE. Skipping build."; \
				echo "Use FORCE_BUILD=1 to force build, or GIT_BASE=<ref> to check against different base."; \
				exit 0; \
			fi; \
		fi; \
		if [ "$(FORCE_BUILD)" = "1" ] || [ "$(FORCE_BUILD)" = "true" ]; then \
			echo "FORCE_BUILD is set, building anyway..."; \
		elif [ -n "$$CHANGED_FILES" ]; then \
			echo "Go files changed. Changed files:"; \
			echo "$$CHANGED_FILES" | sed "s/^/  - /"; \
		elif [ -n "$$UNTRACKED" ]; then \
			echo "Untracked Go files detected. Files:"; \
			echo "$$UNTRACKED" | sed "s/^/  - /"; \
		fi; \
		mkdir -p $(BUILD_DIR); \
		$(GOBUILD) -o $(BUILD_DIR)/$(APP_NAME) -v ./cmd/app'

test: unit-tests ## Run all tests

unit-tests: ## Run unit tests with coverage check (only if Go files changed, requires 89% coverage)
	@bash -c '\
		if [ -n "$(GIT_BASE)" ]; then \
			BASE="$(GIT_BASE)"; \
		else \
			BASE="HEAD"; \
		fi; \
		CHANGED_FILES=$$(git diff --name-only --diff-filter=ACMRTUXB $$BASE -- "*.go" 2>/dev/null || echo ""); \
		if [ -z "$$CHANGED_FILES" ]; then \
			UNTRACKED=$$(git ls-files --others --exclude-standard "*.go" 2>/dev/null || echo ""); \
			if [ -z "$$UNTRACKED" ]; then \
				echo "No Go files changed since $$BASE. Skipping unit tests."; \
				echo "Use FORCE_TEST=1 to force test, or GIT_BASE=<ref> to check against different base."; \
				exit 0; \
			fi; \
		fi; \
		if [ "$(FORCE_TEST)" = "1" ] || [ "$(FORCE_TEST)" = "true" ]; then \
			echo "FORCE_TEST is set, running tests anyway..."; \
		elif [ -n "$$CHANGED_FILES" ]; then \
			echo "Go files changed. Running tests for changed files:"; \
			echo "$$CHANGED_FILES" | sed "s/^/  - /"; \
		elif [ -n "$$UNTRACKED" ]; then \
			echo "Untracked Go files detected. Running tests for:"; \
			echo "$$UNTRACKED" | sed "s/^/  - /"; \
		fi; \
		mkdir -p $(COVERAGE_DIR); \
		$(GOTEST) -v -race -coverprofile=$(COVERAGE_DIR)/unit-coverage.out -covermode=atomic ./internal/...; \
		echo ""; \
		echo "Unit test coverage:"; \
		$(GOCMD) tool cover -func=$(COVERAGE_DIR)/unit-coverage.out | tail -1; \
		echo ""; \
		echo "Checking for 89% coverage..."; \
		COVERAGE_OUTPUT=$$($(GOCMD) tool cover -func=$(COVERAGE_DIR)/unit-coverage.out | tail -1); \
		COVERAGE_PCT=$$(echo "$$COVERAGE_OUTPUT" | awk "{print \$$3}" | sed "s/%//"); \
		if [ -z "$$COVERAGE_PCT" ]; then \
			echo "Error: Could not parse coverage percentage"; \
			exit 1; \
		fi; \
		COVERAGE_INT=$$(echo "$$COVERAGE_PCT" | awk -F. "{print \$$1}"); \
		if [ "$$COVERAGE_INT" -lt 89 ]; then \
			echo "Error: Coverage is $$COVERAGE_PCT%, expected at least 89%"; \
			echo "Functions not fully covered:"; \
			$(GOCMD) tool cover -func=$(COVERAGE_DIR)/unit-coverage.out | grep "github.com/deepak-muley" | grep -v "100.0%" | head -10; \
			exit 1; \
		fi; \
		echo "✓ Coverage is $$COVERAGE_PCT% (meets 89% requirement)"'

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
	@echo "Helm Chart Registry: $(HELM_CHART_REGISTRY) (environment: $(REGISTRY_ENV))"
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
		echo "Helm Chart Registry: $(HELM_CHART_REGISTRY) (environment: $(REGISTRY_ENV))"; \
		echo "Logging in to GHCR..."; \
		echo $$GITHUB_TOKEN | helm registry login ghcr.io -u $(shell git config user.name) --password-stdin; \
		echo "Pushing Helm chart $(HELM_CHART_VERSION) to $(HELM_REPO)..."; \
		helm push chart/$(APP_NAME)-$(HELM_CHART_VERSION).tgz $(HELM_REPO); \
		echo "✓ Helm chart pushed to $(HELM_REPO)"; \
		echo ""; \
		echo "Chart reference:"; \
		echo "  $(HELM_REPO):$(HELM_CHART_VERSION)"; \
		if [ "$(IMMUTABLE)" = "true" ]; then \
			echo "  Git SHA: $(GIT_SHA_FULL)"; \
			echo ""; \
			echo "To get the immutable digest, run:"; \
			echo "  make helm-chart-digest VERSION=$(HELM_CHART_VERSION)"; \
		fi; \
		if [ "$(PUBLIC)" = "true" ] || [ "$(PUBLIC)" = "1" ]; then \
			echo "Making Helm chart public..."; \
			PACKAGE_NAME="$(HELM_CHART_PACKAGE)"; \
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

helm-show-values: ## Show Helm chart values (use CHART_VERSION=0.1.0+sha-abc123 or auto-detects from current commit)
	@bash -c '\
		if [ -f .env.local ]; then \
			. .env.local; \
		fi; \
		if [ -z "$$GITHUB_TOKEN" ]; then \
			echo "GITHUB_TOKEN environment variable is not set"; \
			echo "Create a GitHub Personal Access Token (PAT) with '\''read:packages'\'' permission"; \
			echo "Then either:"; \
			echo "  1. Create .env.local file with: export GITHUB_TOKEN=your_token_here"; \
			echo "  2. Or run: export GITHUB_TOKEN=your_token_here"; \
			exit 1; \
		fi; \
		if [ -n "$(CHART_VERSION)" ]; then \
			CHART_VERSION="$(CHART_VERSION)"; \
		elif [ "$(IMMUTABLE)" = "true" ]; then \
			CHART_VERSION="$(HELM_CHART_VERSION)"; \
		else \
			CHART_VERSION="$(VERSION)"; \
		fi; \
		echo "Showing values for Helm chart version: $$CHART_VERSION"; \
		echo "Chart registry: $(HELM_CHART_REGISTRY) (environment: $(REGISTRY_ENV))"; \
		echo "Note: Helm automatically appends chart name, so full path is: $(HELM_CHART_FULL_PATH)"; \
		echo ""; \
		CHART_FULL_PATH="$(HELM_CHART_FULL_PATH)"; \
		echo "Command:"; \
		echo "  helm show values oci://$$CHART_FULL_PATH --version $$CHART_VERSION"; \
		echo ""; \
		echo $$GITHUB_TOKEN | helm registry login ghcr.io -u $(shell git config user.name) --password-stdin > /dev/null 2>&1; \
		helm show values "oci://$$CHART_FULL_PATH" --version "$$CHART_VERSION"'

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
		echo "Note: Helm automatically appends chart name, so full path is: $(HELM_CHART_FULL_PATH)"; \
		echo $$GITHUB_TOKEN | helm registry login ghcr.io -u $(shell git config user.name) --password-stdin > /dev/null 2>&1; \
		CHART_REF="$(HELM_CHART_FULL_PATH):$$CHART_VERSION"; \
		if command -v crane > /dev/null; then \
			DIGEST=$$(crane digest $$CHART_REF 2>/dev/null); \
			if [ -n "$$DIGEST" ]; then \
				echo ""; \
				echo "Chart digest:"; \
				echo "  $$DIGEST"; \
				echo ""; \
				echo "Immutable reference:"; \
				echo "  $(HELM_REPO)@$$DIGEST"; \
				echo ""; \
				echo "Use this reference in your deployments for immutability:"; \
				echo "  helm install my-app $(HELM_REPO) --version $$CHART_VERSION --oci-registry-config ~/.docker/config.json"; \
				echo "  # Or with digest:"; \
				echo "  helm install my-app $(HELM_REPO)@$$DIGEST --oci-registry-config ~/.docker/config.json"; \
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
					echo "  $(HELM_REPO)@$$DIGEST"; \
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
			echo "  helm show chart $(HELM_REPO) --version $$CHART_VERSION"; \
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

docker-build: ## Build Docker image using buildpacks (only if Go files changed, use IMMUTABLE=false to disable Git SHA, FORCE_BUILD=1 to force)
	@bash -c '\
		if [ -n "$(GIT_BASE)" ]; then \
			BASE="$(GIT_BASE)"; \
		else \
			BASE="HEAD"; \
		fi; \
		CHANGED_FILES=$$(git diff --name-only --diff-filter=ACMRTUXB $$BASE -- "*.go" 2>/dev/null || echo ""); \
		if [ -z "$$CHANGED_FILES" ]; then \
			UNTRACKED=$$(git ls-files --others --exclude-standard "*.go" 2>/dev/null || echo ""); \
			if [ -z "$$UNTRACKED" ]; then \
				if [ "$(FORCE_BUILD)" != "1" ] && [ "$(FORCE_BUILD)" != "true" ]; then \
					echo "No Go files changed since $$BASE. Skipping Docker image build."; \
					echo "Use FORCE_BUILD=1 to force build, or GIT_BASE=<ref> to check against different base."; \
					exit 0; \
				else \
					echo "FORCE_BUILD is set, building Docker image anyway..."; \
				fi; \
			fi; \
		fi; \
		if ! command -v pack > /dev/null; then \
			echo "pack is not installed. Install it from https://buildpacks.io/docs/tools/pack/"; \
			exit 1; \
		fi; \
		if [ -n "$$CHANGED_FILES" ]; then \
			echo "Go files changed. Changed files:"; \
			echo "$$CHANGED_FILES" | sed "s/^/  - /"; \
		elif [ -n "$$UNTRACKED" ]; then \
			echo "Untracked Go files detected. Files:"; \
			echo "$$UNTRACKED" | sed "s/^/  - /"; \
		fi; \
		echo "Building Docker image with version: $(IMAGE_VERSION)"; \
		echo "Container Image Registry: $(IMAGE_REGISTRY) (environment: $(REGISTRY_ENV))"; \
		BUILDER="gcr.io/buildpacks/builder:google-22"; \
		CACHE_IMAGE="$(IMAGE_REGISTRY):cache"; \
		echo "Using builder: $$BUILDER"; \
		echo "Note: First build may be slow (~2-5 min) as it downloads builder image (~1-2GB)"; \
		echo "      Subsequent builds use cache and are much faster (~30-60 sec)"; \
		PACK_ARGS="--builder $$BUILDER --pull-policy if-not-present --cache-image $$CACHE_IMAGE"; \
		GOMODCACHE=$$(go env GOMODCACHE 2>/dev/null || echo ""); \
		if [ -n "$$GOMODCACHE" ] && [ -d "$$GOMODCACHE" ]; then \
			echo "Using Go module cache volume: $$GOMODCACHE"; \
			PACK_ARGS="$$PACK_ARGS --volume $$GOMODCACHE:/go/pkg/mod:ro"; \
		fi; \
		pack build $(IMAGE) \
			$$PACK_ARGS \
			--env GOOGLE_RUNTIME_VERSION=$(GO_VERSION) \
			--env GOOGLE_BUILDABLE=./cmd/app \
			--env PORT=8080 \
			--env METRICS_PORT=9090; \
		echo "✓ Docker image built: $(IMAGE)"; \
		echo "Tip: Use 'docker build' for faster local development builds"'

docker-push: docker-build ## Build and push Docker image (use SIGN=true to sign with cosign, REGISTRY_ENV=dev for dev path)
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
		echo "Container Image Registry: $(IMAGE_REGISTRY) (environment: $(REGISTRY_ENV))"; \
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

setup-metallb-helm: ## Set up MetalLB using Helm chart (for local testing with LoadBalancer services)
	@if ! command -v helm > /dev/null; then \
		echo "helm is not installed. Install it from https://helm.sh/"; \
		exit 1; \
	fi
	@if ! command -v kubectl > /dev/null; then \
		echo "kubectl is not installed"; \
		exit 1; \
	fi
	@if ! command -v docker > /dev/null; then \
		echo "docker is not installed"; \
		exit 1; \
	fi
	./scripts/setup-metallb-helm.sh

kill-port-forwards: ## Kill processes using common port-forward ports (use PORTS=3000,9090 for specific ports, or --all for all common ports)
	@./scripts/kill-port-forwards.sh $(if $(PORTS),$(PORTS),--all)

setup-pre-commit: ## Set up pre-commit hooks using Python virtual environment
	@./scripts/setup-pre-commit.sh

pre-commit: ## Run pre-commit hooks on staged files (requires venv activation: source .venv/bin/activate)
	@if [ ! -d ".venv" ]; then \
		echo "Error: Virtual environment not found. Run 'make setup-pre-commit' first"; \
		exit 1; \
	fi
	@if ! command -v pre-commit > /dev/null; then \
		echo "Error: pre-commit not found. Activate venv first: source .venv/bin/activate"; \
		exit 1; \
	fi
	@pre-commit run

pre-commit-all: ## Run pre-commit hooks on all files (requires venv activation: source .venv/bin/activate)
	@if [ ! -d ".venv" ]; then \
		echo "Error: Virtual environment not found. Run 'make setup-pre-commit' first"; \
		exit 1; \
	fi
	@if ! command -v pre-commit > /dev/null; then \
		echo "Error: pre-commit not found. Activate venv first: source .venv/bin/activate"; \
		exit 1; \
	fi
	@pre-commit run --all-files

pre-commit-update: ## Update pre-commit hooks (requires venv activation: source .venv/bin/activate)
	@if [ ! -d ".venv" ]; then \
		echo "Error: Virtual environment not found. Run 'make setup-pre-commit' first"; \
		exit 1; \
	fi
	@if ! command -v pre-commit > /dev/null; then \
		echo "Error: pre-commit not found. Activate venv first: source .venv/bin/activate"; \
		exit 1; \
	fi
	@pre-commit autoupdate

all: clean deps lint build test ## Run all: clean, deps, lint, build, test
