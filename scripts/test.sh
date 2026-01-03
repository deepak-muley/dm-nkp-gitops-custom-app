#!/bin/bash
set -euo pipefail

# Test script for dm-nkp-gitops-custom-app

echo "Running tests..."

# Run unit tests
echo "Running unit tests..."
go test -v -race -coverprofile=coverage/unit-coverage.out ./internal/...

# Run integration tests if tag is provided
if [ "${1:-}" == "integration" ] || [ "${1:-}" == "all" ]; then
    echo "Running integration tests..."
    go test -v -tags=integration -race ./tests/integration/...
fi

# Run e2e tests if tag is provided
if [ "${1:-}" == "e2e" ] || [ "${1:-}" == "all" ]; then
    echo "Running e2e tests..."
    go test -v -tags=e2e -timeout=30m ./tests/e2e/...
fi

echo "Tests complete!"
