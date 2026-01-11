# Namespace/Platform & Cluster-Wide Footprint Dashboard Guide

## Overview

This guide covers **two comprehensive Grafana dashboards** designed to monitor your Kubernetes cluster at different levels:

1. **Platform Services Footprint Dashboard** - Monitors entire namespaces or collections of namespaces. Perfect for understanding platform services footprint in NKP (Kubernetes Native Platform) deployments.

2. **Cluster-Wide Footprint Dashboard** - Provides an aggregated view of the entire cluster footprint. Ideal for capacity planning, cluster health monitoring, and overall infrastructure assessment.

Both dashboards work together to provide a complete picture: namespace-level insights from the Platform dashboard and cluster-wide aggregated metrics from the Cluster dashboard.

## Features

### 🎯 Key Capabilities

- **Multi-Namespace Monitoring**: Monitor one or multiple namespaces simultaneously using a dropdown selector
- **Resource Type Filtering**: Filter by Kubernetes resource types (Deployments, StatefulSets, DaemonSets, etc.)
- **Extensible to Any Cluster**: Works with any Kubernetes cluster that has Prometheus and kube-state-metrics installed
- **Comprehensive Metrics**: CPU, Memory, Network, Storage, and Resource Quota monitoring
- **Real-time Updates**: Auto-refreshes every 30 seconds with configurable time ranges

## Cluster-Wide Footprint Dashboard

### 🎯 Overview

The **Cluster-Wide Footprint Dashboard** provides an aggregated, cluster-level view of your entire Kubernetes infrastructure. Unlike the namespace-specific dashboard, this dashboard aggregates metrics across all namespaces to show the overall cluster health, capacity, and utilization.

### Key Features

- **Cluster-Level Aggregation**: All metrics aggregated across entire cluster (no namespace filtering)
- **Capacity Planning**: Shows cluster capacity vs utilization for capacity planning decisions
- **Node-Level Distribution**: View resource distribution across nodes
- **Cluster Health Overview**: Quick health check of entire cluster at a glance
- **Resource Efficiency**: Overall cluster resource allocation efficiency

### 📊 Cluster Dashboard Panels

The cluster-wide dashboard includes **17 comprehensive panels**:

#### Cluster Overview (Panels 1-4)
1. **Total Nodes** - Total number of nodes in the cluster
2. **Total Pods** - Total number of pods across entire cluster
3. **Cluster CPU Utilization %** - Overall CPU usage vs cluster capacity
4. **Cluster Memory Utilization %** - Overall memory usage vs cluster capacity

#### Cluster Resource Summary (Panels 5-7)
5. **Cluster CPU Resources** - Stacked view of CPU Usage, Requests, Limits, Capacity, and Allocatable
6. **Cluster Memory Resources** - Stacked view of Memory Usage, Requests, Limits, Capacity, and Allocatable
7. **Cluster Resource Summary Table** - Comprehensive table with all CPU and Memory metrics plus utilization percentages

#### Distribution Views (Panels 8-12)
8. **Pod Distribution by Namespace** - Shows which namespaces consume the most pods
9. **CPU Usage by Namespace** - CPU consumption breakdown by namespace
10. **CPU Resources by Node** - Node-level CPU usage, capacity, and allocatable
11. **Memory Resources by Node** - Node-level memory usage, capacity, and allocatable
12. **Pod Distribution by Node** - Shows pod density across nodes

#### Node-Level Details (Panel 13)
13. **Node Resource Utilization Table** - Detailed table showing per-node CPU/Memory utilization, pod counts, and capacity

#### Cluster Infrastructure (Panels 14-17)
14. **Cluster Resource Counts** - Total counts of Deployments, StatefulSets, DaemonSets, Services, PVCs, and Namespaces
15. **Storage Usage by Storage Class** - Aggregate storage usage across all storage classes
16. **Cluster Network Traffic** - Total network receive/transmit rates across entire cluster
17. **Resource Allocation Efficiency** - Percentage of CPU/Memory requests vs allocatable capacity

### When to Use Cluster-Wide Dashboard

- **Capacity Planning**: Understand overall cluster capacity and utilization trends
- **Infrastructure Decisions**: Make decisions about cluster scaling (add/remove nodes)
- **Cost Analysis**: Get cluster-wide resource consumption for cost calculations
- **Cluster Health**: Quick overview of cluster health and resource availability
- **Node Optimization**: Identify underutilized or overloaded nodes
- **Resource Planning**: Plan for new workloads based on available cluster capacity

### When to Use Namespace Dashboard

- **Namespace-Specific Analysis**: Deep dive into specific namespaces or groups of namespaces
- **Platform Services Monitoring**: Monitor platform services footprint (monitoring, kube-system, etc.)
- **Resource Quota Management**: Understand quota utilization per namespace
- **Multi-Tenant Analysis**: Compare resource usage across different tenants/environments
- **Application Footprint**: Understand resource footprint of specific applications

### 📊 Platform Services Footprint Dashboard Panels

The namespace dashboard includes **25 comprehensive panels** organized into the following categories:

#### Resource Metrics (Panels 1-8)
1. **Total Pods** - Total number of pods across selected namespaces
2. **Deployments** - Number of deployments across selected namespaces
3. **CPU Usage % (vs Limits)** - Aggregate CPU usage percentage relative to limits
4. **Memory Usage % (vs Limits)** - Aggregate memory usage percentage relative to limits
5. **CPU Usage by Namespace** - Time series showing CPU usage, requests, and limits per namespace
6. **Memory Usage by Namespace** - Time series showing memory usage, requests, and limits per namespace
7. **Total CPU Resources** - Stacked view of CPU usage, requests, and limits across all namespaces
8. **Total Memory Resources** - Stacked view of memory usage, requests, and limits across all namespaces

#### Resource Details (Panels 9-13)
9. **Resource Usage per Namespace** - Detailed table with CPU and Memory metrics per namespace
10. **Persistent Volume Usage by Namespace** - Storage usage metrics per namespace
11. **Network Traffic by Namespace** - Network receive/transmit rates per namespace
12. **Resource Count by Type and Namespace** - Breakdown of resource types per namespace
13. **Resource Quota Usage by Namespace** - Resource quota utilization per namespace

#### Service & Network Footprint (Panels 14-18)
14. **Services** - Total number of Kubernetes services across selected namespaces
15. **Endpoints** - Total number of endpoints across selected namespaces
16. **Ingress** - Total number of Ingress resources across selected namespaces
17. **ConfigMaps** - Total number of ConfigMaps across selected namespaces
18. **Service Types by Namespace** - Breakdown of service types (ClusterIP, LoadBalancer, NodePort, ExternalName) per namespace

#### Pod Lifecycle & Health (Panels 19, 23)
19. **Pod Restarts by Namespace** - Total pod restarts and restart rate per namespace
23. **Pod Status Summary by Namespace** - Pod counts by status (Running, Pending, Failed, Ready, Not Ready)

#### Storage & Efficiency (Panels 20-21)
20. **Storage Requests by Storage Class and Namespace** - Storage allocation breakdown by storage class
21. **Resource Efficiency (Usage vs Requests)** - CPU and Memory efficiency percentages showing how well resources are utilized

#### Infrastructure Distribution (Panel 22)
22. **Pod Distribution Across Nodes by Namespace** - Shows which nodes are running pods from selected namespaces

#### Autoscaling & Configuration (Panels 24-25)
24. **HPA Status by Namespace** - Horizontal Pod Autoscaler configuration and current replica counts
25. **Configuration Resources by Namespace** - Counts of Secrets, ConfigMaps, and PVCs per namespace

## Deployment

### Prerequisites

1. **Prometheus** - Must be installed and configured to scrape Kubernetes metrics
2. **kube-state-metrics** - Required for Kubernetes resource metrics (pods, deployments, etc.)
3. **cAdvisor/kubelet** - For container CPU/memory usage metrics
4. **Grafana** - With dashboard discovery enabled (typically via kube-prometheus-stack)
5. **Prometheus ServiceMonitor** - For automatic metric scraping

### Quick Start

#### Option 1: Deploy via Helm Chart (Recommended)

The dashboard is included in the application Helm chart and can be deployed automatically:

```bash
# Deploy with platform footprint dashboard enabled (default)
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  --set grafana.dashboards.enabled=true \
  --set grafana.dashboards.platformFootprint.enabled=true \
  --set grafana.dashboards.platformFootprint.folder="/Platform"
```

#### Option 2: Deploy to Existing NKP Platform

For NKP platforms where Grafana is already deployed:

```bash
# Deploy with NKP-specific values
helm upgrade --install dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  -f chart/dm-nkp-gitops-custom-app/values-nkp.yaml
```

The dashboard will be automatically discovered by Grafana if:
- Grafana is configured with dashboard sidecar enabled (default in kube-prometheus-stack)
- ConfigMap label `grafana_dashboard=1` is present (automatically applied)
- ConfigMap is in the same namespace as Grafana (configured via `grafana.dashboards.namespace`)

### Configuration

#### Helm Values

Configure the dashboard deployment in `values.yaml` or via `--set` flags:

```yaml
grafana:
  dashboards:
    enabled: true
    namespace: "monitoring"  # Namespace where Grafana is deployed
    folder: "/"  # Default folder for app dashboards
    
    # Platform Footprint Dashboard Configuration
    platformFootprint:
      enabled: true  # Enable/disable the dashboard
      folder: "/Platform"  # Grafana folder for platform dashboards
    clusterFootprint:
      enabled: true  # Enable/disable cluster-wide dashboard
      folder: "/Platform"  # Grafana folder for cluster dashboards
```

#### NKP-Specific Configuration

For NKP platforms, update `values-nkp.yaml`:

```yaml
grafana:
  dashboards:
    namespace: "monitoring"  # Verify: kubectl get svc -A | grep grafana
    folder: "/Applications"  # Production folder for application dashboards
    platformFootprint:
      enabled: true
      folder: "/Platform"  # Platform monitoring dashboards
    clusterFootprint:
      enabled: true
      folder: "/Platform"  # Cluster-wide aggregated dashboards
```

### Manual Deployment

If you need to deploy the dashboard manually:

1. **Create ConfigMap**:

```bash
kubectl create configmap platform-footprint-dashboard \
  --from-file=dashboard-platform-footprint.json=chart/dm-nkp-gitops-custom-app/files/grafana/dashboard-platform-footprint.json \
  -n monitoring \
  --dry-run=client -o yaml | \
kubectl label --local -f - grafana_dashboard=1 --dry-run=client -o yaml | \
kubectl annotate --local -f - grafana-folder="/Platform" --dry-run=client -o yaml | \
kubectl apply -f -
```

2. **Verify Dashboard Discovery**:

```bash
# Check ConfigMap is created
kubectl get configmap -n monitoring -l grafana_dashboard=1

# Check Grafana dashboard sidecar logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard | grep platform-footprint
```

## Usage

### Accessing the Dashboard

1. **Port-forward to Grafana**:

```bash
# Find Grafana service
kubectl get svc -A | grep grafana

# Port-forward (adjust namespace and service name as needed)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

2. **Open Grafana UI**:

```
http://localhost:3000
```

3. **Navigate to Dashboards**:

- Go to **Dashboards** → **Browse**
- Look for folder **"Platform"** (or configured folder name)
- Open either:
  - **"Platform Services Footprint - Namespace & Resource Monitoring"** (namespace-level view)
  - **"Cluster-Wide Footprint - Aggregated View"** (cluster-level aggregated view)

### Using the Dropdown Filters

#### Namespace Selector

- **Location**: Top-left dropdown
- **Options**: 
  - Select one or multiple namespaces
  - "All" option to monitor all namespaces
- **Multi-select**: Enabled (you can select multiple namespaces)
- **Auto-refresh**: Automatically updates when namespaces change

**Example Use Cases**:
- Monitor all platform namespaces: `monitoring`, `kube-system`, `kube-public`
- Monitor application namespaces: `default`, `production`, `staging`
- Monitor specific platform service: `monitoring` only

#### Resource Type Selector

- **Location**: Top-right dropdown (next to Namespace)
- **Options**: Filter by Kubernetes resource types
  - Deployment
  - StatefulSet
  - DaemonSet
  - ReplicaSet
  - Job
  - CronJob
  - "All" to include all resource types
- **Single-select**: One resource type at a time
- **Dependent on Namespace**: Options update based on selected namespaces

**Example Use Cases**:
- Monitor only Deployments across selected namespaces
- Monitor DaemonSets (e.g., node agents, log collectors)
- Monitor StatefulSets (e.g., databases, stateful applications)

### Understanding the Metrics

#### CPU Metrics

- **CPU Usage**: Actual CPU consumption in cores (from cAdvisor/kubelet)
- **CPU Requests**: Guaranteed CPU allocation requested by pods
- **CPU Limits**: Maximum CPU allocation allowed for pods
- **CPU Usage %**: `(CPU Usage / CPU Limits) * 100`

**Interpretation**:
- Low usage % (< 50%): Under-utilized resources, consider reducing requests/limits
- Moderate usage % (50-80%): Healthy utilization
- High usage % (> 80%): Risk of throttling, consider increasing limits
- Usage > Limits: Pods are being throttled (check for CPU throttling events)

#### Memory Metrics

- **Memory Usage**: Actual memory consumption (working set) in bytes
- **Memory Requests**: Guaranteed memory allocation requested by pods
- **Memory Limits**: Maximum memory allocation allowed for pods
- **Memory Usage %**: `(Memory Usage / Memory Limits) * 100`

**Interpretation**:
- Low usage % (< 50%): Under-utilized resources
- Moderate usage % (50-80%): Healthy utilization
- High usage % (> 80%): Risk of OOMKilled, consider increasing limits
- Usage > Limits: Pods may be OOMKilled (check pod events)

#### Network Metrics

- **Network Receive**: Incoming network traffic in bytes/second
- **Network Transmit**: Outgoing network traffic in bytes/second

**Interpretation**:
- High receive/transmit: Active services, check for network saturation
- Sudden spikes: Possible traffic anomalies or DDoS
- Zero traffic: Pods may be idle or not receiving traffic

#### Storage Metrics

- **Persistent Volume Usage**: Storage usage per PVC and namespace

**Interpretation**:
- Monitor for disk space exhaustion
- Plan capacity expansion based on growth trends
- Identify storage-heavy namespaces

#### Resource Quota Metrics

- **CPU/Memory Requests/Limits**: Resource quota utilization per namespace

**Interpretation**:
- Approaching quota limits: Risk of pod scheduling failures
- Under-utilized quotas: Opportunity to consolidate or reduce quotas
- Quota violations: Check for pods failing to schedule due to quota limits

## Use Cases

### 1. Platform Services Footprint Analysis

Monitor all platform namespaces to understand overall platform resource consumption:

```yaml
Namespaces: ["monitoring", "kube-system", "kube-public", "kube-node-lease"]
Resource Type: All
```

**What to Look For**:
- Total CPU/Memory footprint of platform services
- Platform overhead percentage of cluster capacity
- Resource quota utilization for platform namespaces
- Storage usage for platform services (logs, metrics, traces)

### 2. Multi-Namespace Application Monitoring

Monitor multiple application namespaces simultaneously:

```yaml
Namespaces: ["production", "staging", "development"]
Resource Type: Deployment
```

**What to Look For**:
- Resource usage comparison across environments
- Identify resource-intensive applications
- Capacity planning for multi-tenant deployments

### 3. Resource Type Analysis

Analyze specific resource types across namespaces:

```yaml
Namespaces: All
Resource Type: DaemonSet
```

**What to Look For**:
- Node-level agents footprint (logging, monitoring, networking)
- Resource consumption per node
- DaemonSet scaling impact on cluster capacity

### 4. Namespace Resource Quota Planning

Monitor resource quota utilization to plan capacity:

```yaml
Namespaces: ["production", "staging"]
Resource Type: All
```

**What to Look For**:
- Current quota usage vs. requested/limits
- Namespaces approaching quota limits
- Opportunities to optimize resource allocation

### 5. Network Traffic Analysis

Monitor network traffic patterns across namespaces:

```yaml
Namespaces: All
Resource Type: All
```

**What to Look For**:
- High-traffic namespaces (microservices communication)
- Network bandwidth usage trends
- Identify network-intensive services

## Customization

### Adding Custom Metrics

To add custom panels or metrics:

1. **Export Dashboard JSON**:
   - Open dashboard in Grafana
   - Click **Dashboard Settings** (gear icon)
   - Click **JSON Model**
   - Copy JSON

2. **Edit Dashboard JSON**:
   - Add new panel definitions to `panels` array
   - Use Prometheus queries with `$namespace` and `$resource` variables
   - Update `chart/dm-nkp-gitops-custom-app/files/grafana/dashboard-platform-footprint.json`

3. **Redeploy Dashboard**:
   ```bash
   helm upgrade dm-nkp-gitops-custom-app ./chart/dm-nkp-gitops-custom-app
   ```

### Customizing Prometheus Queries

The dashboard uses Prometheus variables for dynamic filtering:

- `$namespace`: Selected namespaces (regex pattern)
- `$resource`: Selected resource type (regex pattern)

**Example Query**:
```promql
sum(rate(container_cpu_usage_seconds_total{namespace=~"$namespace", container!="", container!="POD"}[5m])) by (namespace)
```

**Custom Query Examples**:
```promql
# CPU usage for specific resource type
sum(rate(container_cpu_usage_seconds_total{namespace=~"$namespace", pod=~"$resource.*", container!="", container!="POD"}[5m])) by (namespace)

# Pod count by namespace
count(kube_pod_info{namespace=~"$namespace"}) by (namespace)

# Deployment replicas by namespace
sum(kube_deployment_spec_replicas{namespace=~"$namespace"}) by (namespace)
```

### Adjusting Refresh Interval

Update dashboard refresh rate in dashboard JSON:

```json
{
  "refresh": "30s",  // Change to "1m", "5m", etc.
  ...
}
```

Or configure in Grafana UI:
- Click **Dashboard Settings** → **General**
- Set **Refresh** interval

### Changing Time Range

Default time range is "Last 1 hour". Modify in dashboard JSON:

```json
{
  "time": {
    "from": "now-1h",  // Change to "now-6h", "now-24h", etc.
    "to": "now"
  }
}
```

Or use Grafana time picker in UI.

## Troubleshooting

### Dashboard Not Appearing in Grafana

1. **Check ConfigMap exists**:
   ```bash
   kubectl get configmap -n monitoring -l grafana_dashboard=1 | grep platform-footprint
   ```

2. **Verify Grafana dashboard discovery**:
   ```bash
   # Check Grafana deployment has sidecar enabled
   kubectl get deployment -n monitoring -l app.kubernetes.io/name=grafana -o yaml | grep -A 5 sidecar
   
   # Check sidecar logs
   kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard
   ```

3. **Check ConfigMap labels/annotations**:
   ```bash
   kubectl get configmap -n monitoring <dashboard-name> -o yaml | grep -E "grafana_dashboard|grafana-folder"
   ```

### No Data in Panels

1. **Verify Prometheus is scraping metrics**:
   ```bash
   # Port-forward to Prometheus
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   
   # Check targets
   curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up")'
   ```

2. **Check metric availability**:
   ```bash
   # Query Prometheus directly
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   curl 'http://localhost:9090/api/v1/query?query=kube_pod_info' | jq
   ```

3. **Verify kube-state-metrics is running**:
   ```bash
   kubectl get pods -A | grep kube-state-metrics
   kubectl logs -n monitoring -l app.kubernetes.io/name=kube-state-metrics
   ```

4. **Check cAdvisor/kubelet metrics**:
   ```bash
   # Check if node exporter or cAdvisor is scraping
   curl 'http://localhost:9090/api/v1/query?query=container_cpu_usage_seconds_total' | jq
   ```

### Dropdown Shows Empty Options

1. **Verify namespaces exist**:
   ```bash
   kubectl get namespaces
   ```

2. **Check Prometheus has namespace labels**:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   curl 'http://localhost:9090/api/v1/label/namespace/values' | jq
   ```

3. **Verify resource type labels**:
   ```bash
   curl 'http://localhost:9090/api/v1/label/created_by_kind/values' | jq
   ```

### Performance Issues

1. **Too many namespaces selected**: Limit to specific namespaces instead of "All"
2. **Time range too large**: Reduce time range (e.g., from 24h to 6h)
3. **Complex queries**: Consider using recording rules in Prometheus
4. **Prometheus query timeout**: Increase `evaluation_interval` in Prometheus config

## Advanced Configuration

### Recording Rules for Better Performance

Create Prometheus recording rules to pre-aggregate metrics:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: namespace-platform-footprint
  namespace: monitoring
spec:
  groups:
    - name: namespace_footprint
      interval: 30s
      rules:
        - record: namespace:cpu_usage:rate5m
          expr: sum(rate(container_cpu_usage_seconds_total{container!="", container!="POD"}[5m])) by (namespace)
        - record: namespace:memory_usage:sum
          expr: sum(container_memory_working_set_bytes{container!="", container!="POD"}) by (namespace)
```

Then update dashboard queries to use recording rules:
```promql
namespace:cpu_usage:rate5m{namespace=~"$namespace"}
```

### Alerting Rules

Create alerts based on dashboard metrics:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: namespace-platform-alerts
  namespace: monitoring
spec:
  groups:
    - name: namespace_footprint_alerts
      rules:
        - alert: NamespaceHighCPUUsage
          expr: |
            sum(rate(container_cpu_usage_seconds_total{namespace=~".+"}[5m])) / 
            sum(kube_pod_container_resource_limits{resource="cpu"}) * 100 > 80
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Namespace {{ $labels.namespace }} has high CPU usage"
```

## Additional Enhancements for Complete Footprint Understanding

The dashboard provides a comprehensive view, but here are additional metrics and panels you can add for even deeper insights:

### 💰 Cost & Financial Metrics

**1. Resource Cost Allocation**
   - **Panel**: Cost per namespace based on resource requests/usage
   - **Query Example**: 
     ```promql
     # CPU cost (assuming $X per CPU core)
     sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace) * <cost_per_core>
     
     # Memory cost (assuming $Y per GB)
     sum(kube_pod_container_resource_requests{resource="memory"}) by (namespace) / 1024 / 1024 / 1024 * <cost_per_gb>
     ```
   - **Use Case**: Understand financial impact of namespaces for budgeting and chargeback

**2. Storage Cost Breakdown**
   - **Panel**: Storage costs by storage class and namespace
   - **Query Example**:
     ```promql
     sum(kube_persistentvolumeclaim_resource_requests_storage_bytes{storageclass=~".+"}) by (namespace, storageclass) * <cost_per_gb_per_storage_class>
     ```
   - **Use Case**: Identify expensive storage classes and optimize storage usage

### 🔒 Security & Compliance Footprint

**3. Network Policy Coverage**
   - **Panel**: NetworkPolicy count and coverage percentage per namespace
   - **Query Example**:
     ```promql
     count(kube_networkpolicy_info{namespace=~"$namespace"}) by (namespace)
     ```
   - **Use Case**: Ensure security policies are applied across namespaces

**4. Pod Security Standards Compliance**
   - **Panel**: Pods violating security policies (runAsNonRoot, readOnlyRootFilesystem, etc.)
   - **Query Example**:
     ```promql
     # Pods running as root (if available in metrics)
     count(kube_pod_info{run_as_root="true", namespace=~"$namespace"}) by (namespace)
     ```
   - **Use Case**: Security compliance and audit requirements

**5. Service Account Usage**
   - **Panel**: Service account usage per namespace
   - **Query Example**:
     ```promql
     count(kube_pod_info{namespace=~"$namespace"}) by (namespace, service_account)
     ```
   - **Use Case**: Identify over-privileged service accounts and security risks

### 📈 Performance & Efficiency Metrics

**6. Request Saturation Metrics**
   - **Panel**: Percentage of pods with requests near limits (risk of throttling)
   - **Query Example**:
     ```promql
     # CPU saturation: pods with usage > 80% of limits
     count((rate(container_cpu_usage_seconds_total[5m]) / kube_pod_container_resource_limits{resource="cpu"}) > 0.8) by (namespace)
     ```
   - **Use Case**: Identify pods at risk of resource throttling before issues occur

**7. Resource Waste Analysis**
   - **Panel**: Unused resource requests (low usage vs high requests)
   - **Query Example**:
     ```promql
     # Low CPU efficiency: usage < 20% of requests
     sum(kube_pod_container_resource_requests{resource="cpu"} - rate(container_cpu_usage_seconds_total[5m])) by (namespace) where (rate(container_cpu_usage_seconds_total[5m]) / kube_pod_container_resource_requests{resource="cpu"} < 0.2)
     ```
   - **Use Case**: Optimize resource allocation and reduce costs

**8. Pod Density Metrics**
   - **Panel**: Pods per node, resources per pod
   - **Query Example**:
     ```promql
     count(kube_pod_info{namespace=~"$namespace"}) by (node) / count(kube_node_info)
     ```
   - **Use Case**: Optimize cluster utilization and pod scheduling

### 🌐 Network & Connectivity Footprint

**9. Ingress/LoadBalancer IP Allocation**
   - **Panel**: LoadBalancer services and external IP usage
   - **Query Example**:
     ```promql
     count(kube_service_info{type="LoadBalancer", namespace=~"$namespace"}) by (namespace)
     ```
   - **Use Case**: Monitor external IP usage and costs (some clouds charge for LoadBalancers)

**10. DNS Query Patterns** (if CoreDNS metrics available)
    - **Panel**: DNS queries per namespace
    - **Query Example**:
      ```promql
      sum(rate(coredns_dns_requests_total{namespace=~"$namespace"}[5m])) by (namespace)
      ```
    - **Use Case**: Understand service discovery patterns and DNS load

**11. Network Policy Traffic** (if CNI metrics available)
    - **Panel**: Allowed/denied traffic by network policy
    - **Query Example**: Depends on CNI (Cilium, Calico, etc.)
    - **Use Case**: Validate network policy effectiveness

### 🔄 Lifecycle & Operational Metrics

**12. Pod Age Distribution**
    - **Panel**: Average pod age, pod churn rate
    - **Query Example**:
      ```promql
      # Pod age in hours
      (time() - kube_pod_created{namespace=~"$namespace"}) / 3600
      ```
    - **Use Case**: Identify stable vs frequently restarted pods

**13. Deployment Rollout Status**
    - **Panel**: Rollout progress, replica set versions
    - **Query Example**:
      ```promql
      kube_deployment_status_replicas_available{namespace=~"$namespace"} / kube_deployment_spec_replicas{namespace=~"$namespace"} * 100
      ```
    - **Use Case**: Monitor deployment health and rollout progress

**14. Job & CronJob Execution Metrics**
    - **Panel**: Successful/failed job executions, cron job schedules
    - **Query Example**:
      ```promql
      count(kube_job_status_succeeded{namespace=~"$namespace"}) by (namespace)
      count(kube_job_status_failed{namespace=~"$namespace"}) by (namespace)
      ```
    - **Use Case**: Monitor batch job health and identify failures

### 📦 Application & Service Mesh Metrics

**15. Service Mesh Metrics** (if Istio/Linkerd available)
    - **Panel**: Request rates, error rates, latency (p50/p95/p99) by service
    - **Query Example** (Istio):
      ```promql
      sum(rate(istio_requests_total{namespace=~"$namespace"}[5m])) by (namespace, destination_service_name)
      ```
    - **Use Case**: Understand microservices communication patterns and performance

**16. API Gateway Metrics** (if Traefik/Kong/Nginx Ingress)
    - **Panel**: Request rates, response times, error rates by ingress
    - **Query Example** (Traefik):
      ```promql
      sum(rate(traefik_entrypoint_requests_total{namespace=~"$namespace"}[5m])) by (namespace, entrypoint)
      ```
    - **Use Case**: Monitor external traffic patterns and API performance

### 🗄️ Stateful Workload Footprint

**17. StatefulSet & Database Metrics**
    - **Panel**: StatefulSet replicas, persistent volume claims per StatefulSet
    - **Query Example**:
      ```promql
      count(kube_statefulset_status_replicas{namespace=~"$namespace"}) by (namespace, statefulset)
      ```
    - **Use Case**: Monitor stateful workload distribution and storage requirements

**18. Backup & Snapshot Status** (if backup operators available)
    - **Panel**: Successful/failed backups per namespace
    - **Query Example**: Depends on backup solution (Velero, etc.)
    - **Use Case**: Ensure data protection compliance

### 🔍 Observability & Logging Footprint

**19. Log Volume & Retention**
    - **Panel**: Log volume per namespace, log retention costs
    - **Query Example** (Loki):
      ```promql
      sum(rate(loki_distributor_lines_received_total{namespace=~"$namespace"}[5m])) by (namespace)
      ```
    - **Use Case**: Optimize log retention policies and costs

**20. Metrics Cardinality**
    - **Panel**: Unique metric series per namespace
    - **Query Example**:
      ```promql
      count({__name__=~".+", namespace=~"$namespace"}) by (namespace)
      ```
    - **Use Case**: Identify high-cardinality metrics causing Prometheus storage issues

### 🎯 Multi-Cluster & Federation Metrics

**21. Multi-Cluster Resource Distribution**
    - **Panel**: Resource usage across multiple clusters (requires federation)
    - **Query Example**: Requires Prometheus federation setup
    - **Use Case**: Global footprint analysis across clusters

**22. GitOps Sync Status** (if ArgoCD/Flux available)
    - **Panel**: Application sync status, drift detection
    - **Query Example**: Depends on GitOps tool metrics
    - **Use Case**: Ensure infrastructure as code compliance

### 📊 Custom Business Metrics Integration

**23. Business Metrics Correlation**
    - **Panel**: Correlate Kubernetes resource usage with business metrics (requests, users, revenue)
    - **Query Example**: Combine custom metrics with Kubernetes metrics
    - **Use Case**: Understand resource efficiency in business context

**24. SLA/SLO Compliance**
    - **Panel**: Uptime, error rates, latency SLOs per namespace/service
    - **Query Example**: Combine availability metrics with business SLOs
    - **Use Case**: Ensure service level objectives are met

### 🛠️ Implementation Recommendations

To add these enhancements:

1. **Identify Available Metrics**: Use Prometheus explore to find what metrics are available in your cluster
   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   # Open http://localhost:9090 and explore metrics
   ```

2. **Create Custom Panels**: Add new panels to the dashboard JSON following the existing pattern

3. **Use Recording Rules**: For expensive queries, create Prometheus recording rules to pre-aggregate

4. **Enable Additional Exporters**: 
   - **Cost**: Install kubecost or cloud provider cost exporters
   - **Security**: Enable security audit metrics exporters
   - **Network**: Enable CNI-specific metrics (Cilium, Calico)

5. **Integrate External Tools**: 
   - **Cost Management**: Kubecost, CloudHealth, Spot.io
   - **Security**: Falco, OPA Gatekeeper metrics
   - **Service Mesh**: Istio, Linkerd observability

6. **Dashboard Organization**: Create separate dashboards for:
   - Cost & Financial Analysis
   - Security & Compliance
   - Performance Optimization
   - Network & Connectivity
   - Multi-Cluster Overview

## Best Practices

1. **Namespace Selection**: Start with specific namespaces, then expand to "All" for overview
2. **Resource Type Filtering**: Use resource type filter to focus on specific workload types
3. **Time Range**: Use shorter time ranges (1-6 hours) for real-time monitoring, longer (24h-7d) for trend analysis
4. **Regular Reviews**: Schedule weekly/monthly reviews of platform footprint to identify optimization opportunities
5. **Documentation**: Document namespace purposes and expected resource consumption
6. **Capacity Planning**: Use dashboard metrics for capacity planning and resource quota allocation
7. **Cost Optimization**: Regularly review resource efficiency metrics to identify waste
8. **Security Monitoring**: Monitor network policies, pod security, and service account usage
9. **Performance Tuning**: Use efficiency metrics to right-size resource requests and limits
10. **Multi-Dimensional Analysis**: Combine metrics from different categories for comprehensive insights

## Related Documentation

- [Grafana Dashboards Setup Guide](./GRAFANA_DASHBOARDS_SETUP.md)
- [NKP Deployment Guide](./NKP_DEPLOYMENT.md)
- [Helm Chart Installation Reference](./HELM_CHART_INSTALLATION_REFERENCE.md)
- [Platform Dependencies](./PLATFORM_DEPENDENCIES.md)

## Support

For issues or questions:
1. Check [Troubleshooting](#troubleshooting) section
2. Review Grafana and Prometheus logs
3. Verify all prerequisites are met
4. Consult [NKP Documentation](./NKP_DEPLOYMENT.md) for platform-specific issues
