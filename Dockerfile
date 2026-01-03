# This Dockerfile is provided as an alternative to buildpacks
# The recommended approach is to use buildpacks (see Makefile docker-build target)

# Build stage
FROM golang:1.23-alpine AS builder

WORKDIR /build

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o app ./cmd/app

# Final stage - distroless
FROM gcr.io/distroless/static:nonroot

WORKDIR /

COPY --from=builder /build/app /app

USER nonroot:nonroot

EXPOSE 8080 9090

ENV PORT=8080
ENV METRICS_PORT=9090

ENTRYPOINT ["/app"]

