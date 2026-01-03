# Development Guide

This guide covers the development workflow for dm-nkp-gitops-custom-app.

## Prerequisites

- Go 1.25 or later
- Make
- Git

## Development Setup

1. **Clone and setup**:
   ```bash
   git clone https://github.com/deepak-muley/dm-nkp-gitops-custom-app.git
   cd dm-nkp-gitops-custom-app
   make deps
   ```

2. **Run locally**:
   ```bash
   make build
   ./bin/dm-nkp-gitops-custom-app
   ```

## Code Structure

### Application Entry Point

- `cmd/app/main.go`: Main entry point that initializes metrics and starts the server

### Internal Packages

- `internal/metrics/`: Prometheus metrics definitions and initialization
- `internal/server/`: HTTP server implementation with health/ready endpoints

### Testing

- `internal/*/*_test.go`: Unit tests
- `tests/integration/`: Integration tests (require running server)
- `tests/e2e/`: End-to-end tests (require kind cluster)

## Development Workflow

1. **Make changes** to the code
2. **Format code**: `make fmt`
3. **Run linters**: `make lint`
4. **Run tests**: `make test`
5. **Build**: `make build`
6. **Test locally**: Run the binary and test endpoints

## Adding New Metrics

To add a new Prometheus metric:

1. Define the metric in `internal/metrics/metrics.go`:
   ```go
   var MyNewMetric = promauto.NewCounter(prometheus.CounterOpts{
       Name: "my_new_metric_total",
       Help: "Description of my metric",
   })
   ```

2. Use it in your code:
   ```go
   metrics.MyNewMetric.Inc()
   ```

3. Add tests in `internal/metrics/metrics_test.go`

## Adding New Endpoints

1. Add handler function in `internal/server/server.go`:
   ```go
   func handleNewEndpoint(w http.ResponseWriter, r *http.Request) {
       // Your handler logic
   }
   ```

2. Register in `New()` function:
   ```go
   mux.HandleFunc("/new-endpoint", handleNewEndpoint)
   ```

3. Add tests in `internal/server/server_test.go`

## Environment Variables

- `PORT`: HTTP server port (default: 8080)
- `METRICS_PORT`: Metrics server port (default: 9090)

## Debugging

### Local Debugging

Run the application with verbose logging:
```bash
./bin/dm-nkp-gitops-custom-app
```

### Testing Metrics

1. Start the application
2. Make requests: `curl http://localhost:8080/`
3. Check metrics: `curl http://localhost:9090/metrics`

### Integration Testing

Run integration tests that start a real server:
```bash
make integration-tests
```

## Code Style

- Follow Go standard formatting (`go fmt`)
- Use `golangci-lint` for linting (configured in `.golangci.yml`)
- Write tests for all new functionality
- Use descriptive variable and function names

## Dependencies

Update dependencies:
```bash
go get -u ./...
go mod tidy
```

## Building for Different Platforms

```bash
# Linux
GOOS=linux GOARCH=amd64 make build

# macOS
GOOS=darwin GOARCH=amd64 make build

# Windows
GOOS=windows GOARCH=amd64 make build
```

