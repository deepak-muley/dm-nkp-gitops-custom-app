# OTLP gRPC vs HTTP: When to Use Each Protocol

This guide helps you choose between OTLP gRPC and HTTP protocols for OpenTelemetry Collector receivers (source) and exporters (target).

## Quick Comparison

| Aspect | **gRPC** (port 4317) | **HTTP** (port 4318) |
|--------|---------------------|---------------------|
| **Performance** | ✅ Better (binary protobuf, streaming) | Slightly slower (JSON or protobuf) |
| **Compression** | ✅ Native support | Requires explicit config |
| **Firewall/Proxy** | ❌ May be blocked (HTTP/2) | ✅ Easier to pass through |
| **Load Balancers** | Needs HTTP/2-aware LB | ✅ Works with any LB |
| **Debugging** | Harder to inspect | ✅ Easier (JSON readable) |
| **Browser/Serverless** | ❌ Not supported | ✅ Supported |
| **Connection Model** | Long-lived, multiplexed | Request/response |
| **Retries** | Built-in | Application-level |

## Receivers (Source → Collector)

Receivers define how your applications send telemetry **to** the collector.

### Configuration Example

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
```

### When to Use Each Protocol

| Use Case | Protocol | Reason |
|----------|----------|--------|
| **Go/Java/Python SDK** (in-cluster) | gRPC (4317) | Better performance, native SDK support |
| **Browser apps** (RUM/Web) | HTTP (4318) | Browsers don't support gRPC natively |
| **Serverless/Lambda** | HTTP (4318) | Simpler, no long-lived connections needed |
| **Behind corporate proxy** | HTTP (4318) | Proxies often block HTTP/2 traffic |
| **High-throughput services** | gRPC (4317) | Streaming & multiplexing benefits |
| **Mobile applications** | HTTP (4318) | Better compatibility across networks |
| **Microservices (same cluster)** | gRPC (4317) | Optimal performance |

### Best Practice

**Expose both protocols** on your collector to support all client types:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
```

## Exporters (Collector → Backend)

Exporters define how the collector sends telemetry **to** backend systems.

### Configuration Examples

```yaml
exporters:
  # gRPC exporter (for Tempo, Jaeger, etc.)
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true

  # HTTP exporter (for Loki, cloud vendors, cross-network)
  otlphttp/loki:
    endpoint: http://loki-gateway:80/otlp
    tls:
      insecure: true
```

### Backend-Specific Recommendations

| Backend | Exporter Type | Endpoint Example | Notes |
|---------|---------------|------------------|-------|
| **Tempo** | `otlp` (gRPC) | `tempo:4317` | Native gRPC, best performance |
| **Jaeger** | `otlp` (gRPC) | `jaeger:4317` | Native gRPC support |
| **Loki 3.0+** | `otlphttp` | `http://loki:80/otlp` | Loki exposes HTTP `/otlp` endpoint |
| **Prometheus** | `prometheus` | N/A (scrape model) | Not OTLP - uses pull model |
| **Datadog** | `otlphttp` | Check vendor docs | HTTP for firewall traversal |
| **New Relic** | `otlphttp` | Check vendor docs | HTTP preferred |
| **Grafana Cloud** | `otlphttp` | Check vendor docs | HTTP with auth headers |
| **AWS X-Ray** | `otlphttp` | Check vendor docs | HTTP for cloud integration |

### Network Topology Recommendations

| Scenario | Protocol | Reason |
|----------|----------|--------|
| **Same Kubernetes cluster** | gRPC | Optimal performance, no network barriers |
| **Cross-cluster (same VPC)** | gRPC | Usually works, test connectivity |
| **Cross-network/Internet** | HTTP | Firewall/proxy friendly |
| **Through API Gateway** | HTTP | Most gateways handle HTTP better |
| **Direct pod-to-pod** | gRPC | Best latency and throughput |

## Protocol Deep Dive

### gRPC Advantages

1. **Binary Protocol**: Uses Protocol Buffers for efficient serialization
2. **HTTP/2**: Multiplexing, header compression, bidirectional streaming
3. **Streaming**: Can stream data continuously without reconnecting
4. **Built-in Features**: Load balancing, retries, deadlines
5. **Strong Typing**: Schema enforcement via protobuf

### HTTP Advantages

1. **Universal Compatibility**: Works everywhere HTTP works
2. **Debugging**: JSON payloads are human-readable
3. **Proxy-Friendly**: Standard HTTP/1.1 works through any proxy
4. **Simpler Setup**: No special client libraries needed
5. **Firewall-Friendly**: Port 80/443 usually allowed

## Common Patterns

### Pattern 1: Full In-Cluster Setup (Recommended)

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

exporters:
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true
  otlphttp/loki:
    endpoint: http://loki-gateway:80/otlp
    tls:
      insecure: true
  prometheus:
    endpoint: 0.0.0.0:8889

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [otlp/tempo]
    logs:
      receivers: [otlp]
      exporters: [otlphttp/loki]
    metrics:
      receivers: [otlp]
      exporters: [prometheus]
```

### Pattern 2: Edge Collector (Receiving from External Sources)

```yaml
receivers:
  otlp:
    protocols:
      # Only HTTP for external traffic
      http:
        endpoint: 0.0.0.0:4318
        cors:
          allowed_origins:
            - "https://myapp.example.com"

exporters:
  # Forward to central collector via gRPC
  otlp:
    endpoint: central-collector:4317
    tls:
      insecure: false
      cert_file: /certs/client.crt
      key_file: /certs/client.key
```

### Pattern 3: Gateway/Sidecar Pattern

```yaml
# Sidecar collector (per-pod)
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 127.0.0.1:4317  # localhost only

exporters:
  otlp:
    endpoint: otel-gateway:4317  # Central gateway
    tls:
      insecure: true
```

## TLS Configuration

### gRPC with TLS

```yaml
exporters:
  otlp/secure:
    endpoint: tempo.prod:4317
    tls:
      insecure: false
      ca_file: /certs/ca.crt
      cert_file: /certs/client.crt
      key_file: /certs/client.key
```

### HTTP with TLS

```yaml
exporters:
  otlphttp/secure:
    endpoint: https://loki.prod:443/otlp
    tls:
      insecure: false
      ca_file: /certs/ca.crt
```

## Troubleshooting

### gRPC Issues

| Problem | Solution |
|---------|----------|
| Connection refused | Check if port 4317 is exposed and service is running |
| TLS handshake failed | Verify certificates and CA chain |
| Load balancer issues | Use HTTP/2-aware LB or client-side load balancing |
| Proxy blocking | Switch to HTTP or use gRPC-Web |

### HTTP Issues

| Problem | Solution |
|---------|----------|
| 404 Not Found | Check endpoint URL path (e.g., `/v1/traces`) |
| CORS errors | Configure CORS in receiver for browser clients |
| Timeout | Increase timeout, check network path |
| Auth failures | Verify headers and credentials |

## Decision Flowchart

```
Start
  │
  ▼
Is it within the same Kubernetes cluster?
  │
  ├─ YES → Does the backend support gRPC natively?
  │          │
  │          ├─ YES → Use gRPC (otlp)
  │          │
  │          └─ NO → Use HTTP (otlphttp)
  │
  └─ NO → Is there a firewall/proxy between?
           │
           ├─ YES → Use HTTP (otlphttp)
           │
           └─ NO → Is it high-throughput?
                    │
                    ├─ YES → Use gRPC (otlp)
                    │
                    └─ NO → Either works, prefer HTTP for simplicity
```

## Summary

| Scenario | Receiver | Exporter |
|----------|----------|----------|
| **Default/Unknown** | Both gRPC + HTTP | Match backend's native protocol |
| **Performance-critical** | gRPC | gRPC |
| **Browser/Web clients** | HTTP required | N/A |
| **Cross-network** | HTTP preferred | HTTP |
| **Debugging/Development** | HTTP (readable) | HTTP |

**Golden Rule**: When in doubt, expose both protocols on receivers and use the backend's native protocol for exporters.
