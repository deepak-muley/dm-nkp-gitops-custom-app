.PHONY: help build test unit-tests integration-tests e2e-tests clean lint fmt vet deps helm-chart push-helm-chart docker-build docker-push kubesec kubesec-helm

# Variables
APP_NAME := dm-nkp-gitops-custom-app
VERSION := 0.1.0
REGISTRY := ghcr.io/deepak-muley/dm-nkp-gitops-custom-app
IMAGE := $(REGISTRY)/$(APP_NAME):$(VERSION)
HELM_CHART_NAME := $(APP_NAME)
HELM_CHART_VERSION := $(VERSION)
HELM_REPO := oci://$(REGISTRY)
GO_VERSION := 1.25
BUILD_DIR := bin
COVERAGE_DIR := coverage

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

helm-chart: ## Package Helm chart
	@if ! command -v helm > /dev/null; then \
		echo "helm is not installed. Install it from https://helm.sh/"; \
		exit 1; \
	fi
	helm package chart/$(APP_NAME) --version $(HELM_CHART_VERSION) --app-version $(VERSION) -d chart/
	@echo "Helm chart packaged: chart/$(APP_NAME)-$(HELM_CHART_VERSION).tgz"

push-helm-chart: helm-chart ## Push Helm chart to OCI registry
	@if ! command -v helm > /dev/null; then \
		echo "helm is not installed. Install it from https://helm.sh/"; \
		exit 1; \
	fi
	helm push chart/$(APP_NAME)-$(HELM_CHART_VERSION).tgz $(HELM_REPO)
	@echo "Helm chart pushed to $(HELM_REPO)"

docker-build: ## Build Docker image using buildpacks
	@if ! command -v pack > /dev/null; then \
		echo "pack is not installed. Install it from https://buildpacks.io/docs/tools/pack/"; \
		exit 1; \
	fi
	pack build $(IMAGE) \
		--builder gcr.io/buildpacks/builder:google-22 \
		--env GOOGLE_RUNTIME_VERSION=$(GO_VERSION) \
		--env GOOGLE_BUILDABLE=./cmd/app \
		--env PORT=8080 \
		--env METRICS_PORT=9090

docker-push: docker-build ## Build and push Docker image
	@if [ -z "$(GITHUB_TOKEN)" ]; then \
		echo "GITHUB_TOKEN environment variable is not set"; \
		exit 1; \
	fi
	docker login ghcr.io -u $(shell git config user.name) -p $(GITHUB_TOKEN)
	docker push $(IMAGE)
	@echo "Image pushed to $(IMAGE)"

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

