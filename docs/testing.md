# Testing Guide

This guide covers the testing strategy and how to run tests for dm-nkp-gitops-custom-app.

## Test Types

### Unit Tests

Unit tests test individual components in isolation without external dependencies.

**Location**: `internal/*/*_test.go`

**Run**:

```bash
make unit-tests
```

**Coverage**: Tests cover metrics initialization, metric updates, and HTTP handlers.

### Integration Tests

Integration tests test components working together, typically requiring a running server.

**Location**: `tests/integration/`

**Run**:

```bash
make integration-tests
```

**Requirements**:

- No external dependencies (server starts in test)
- Tests actual HTTP endpoints
- Verifies metrics endpoint

### End-to-End (E2E) Tests

E2E tests test the complete application in a real environment (Kubernetes cluster).

**Location**: `tests/e2e/`

**Run**:

```bash
make e2e-tests
```

**Requirements**:

- `kind` installed
- `kubectl` configured
- `curl` available

## Running Tests

### Run All Tests

```bash
make test
```

### Run Specific Test Type

```bash
# Unit tests only
make unit-tests

# Integration tests only
make integration-tests

# E2E tests only
make e2e-tests
```

### Run Tests with Coverage

```bash
go test -v -race -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

### Run Specific Test Package

```bash
go test -v ./internal/metrics/...
go test -v ./internal/server/...
```

### Run Specific Test

```bash
go test -v -run TestSpecificTest ./internal/metrics/...
```

## Test Framework

The project uses:

- **Ginkgo**: BDD-style testing framework
- **Gomega**: Matcher library for assertions

### Writing Tests

Example unit test structure:

```go
package metrics

import (
    . "github.com/onsi/ginkgo/v2"
    . "github.com/onsi/gomega"
)

var _ = Describe("Metrics", func() {
    BeforeEach(func() {
        // Setup
    })

    AfterEach(func() {
        // Cleanup
    })

    Describe("Counter metrics", func() {
        It("should increment counter", func() {
            // Test implementation
            Expect(result).To(Equal(expected))
        })
    })
})
```

## Test Tags

Tests use build tags to separate test types:

- **Unit tests**: No tags (default)
- **Integration tests**: `//go:build integration`
- **E2E tests**: `//go:build e2e`

## Continuous Integration

Tests run automatically in GitHub Actions:

1. **Unit tests**: Run on every push/PR
2. **Integration tests**: Run on every push/PR
3. **E2E tests**: Run on every push/PR (requires kind)

See `.github/workflows/ci.yml` for CI configuration.

## Test Coverage

View coverage report:

```bash
make unit-tests
go tool cover -html=coverage/unit-coverage.out
```

Coverage target: >80% for production code.

## Debugging Tests

### Verbose Output

```bash
go test -v ./...
```

### Run Single Test

```bash
go test -v -run TestName ./package/...
```

### Debug with Delve

```bash
dlv test ./internal/metrics/
```

## Integration Test Details

Integration tests:

- Start a real HTTP server
- Make actual HTTP requests
- Verify responses and metrics
- Clean up after tests

Example:

```go
BeforeEach(func() {
    srv = server.New("8080", "9090")
    go srv.Start()
    // Wait for server to be ready
})

AfterEach(func() {
    srv.Shutdown(ctx)
})
```

## E2E Test Details

E2E tests:

- Build the application binary
- Start the application
- Test endpoints
- Optionally test Kubernetes deployment

Requirements:

- `kind` for local Kubernetes cluster
- `kubectl` for cluster interaction
- `curl` for HTTP requests

## Best Practices

1. **Test Isolation**: Each test should be independent
2. **Cleanup**: Always clean up resources in AfterEach
3. **Descriptive Names**: Use clear test descriptions
4. **Test Coverage**: Aim for high coverage of critical paths
5. **Fast Tests**: Keep unit tests fast (< 1s total)
6. **Realistic Tests**: Integration tests should reflect real usage

## Troubleshooting

### Tests Fail Locally but Pass in CI

- Check Go version matches
- Ensure dependencies are up to date: `make deps`
- Clear test cache: `go clean -testcache`

### Integration Tests Fail

- Check if ports 8080/9090 are available
- Verify no other instance is running
- Check firewall settings

### E2E Tests Fail

- Verify `kind` is installed: `kind version`
- Check `kubectl` is configured: `kubectl cluster-info`
- Ensure `curl` is available: `which curl`
