# Observability: DCGM Exporter and Prometheus Stack

**Component:** DCGM Exporter + Prometheus + Grafana  
**Objective:** Monitor GPU utilization, VRAM usage, and per-pod metrics  
**Namespace:** monitoring  

---

## Prerequisites

Ensure workloads are deployed from `03-workloads-and-memory.md`:

```bash
# Verify workloads are running
kubectl get pods -n ml-workloads

# Verify namespace exists
kubectl get namespaces | grep monitoring
```

---

## Step 1: Install kube-prometheus-stack

The kube-prometheus-stack includes Prometheus, Grafana, Alertmanager, and default dashboards.

### Install via Helm

```bash
# Create namespace (if not exists)
kubectl create namespace monitoring

# Add Prometheus Community repository (if not added)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 56.0.0 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30030
```

**Helm Values Explained:**
- `prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false`: Allow Prometheus to discover ServiceMonitors outside the Helm release (required for DCGM)
- `grafana.adminPassword=admin`: Set Grafana admin password (change in production)
- `grafana.service.type=NodePort`: Expose Grafana via NodePort for bare-metal access
- `grafana.service.nodePort=30030`: Specific NodePort for Grafana

### Verify Installation

```bash
# Check Prometheus pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

# Expected output:
# NAME                                            READY   STATUS    RESTARTS   AGE
# kube-prometheus-stack-prometheus-0             2/2     Running   0          30s

# Check Grafana pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Expected output:
# NAME                                            READY   STATUS    RESTARTS   AGE
# kube-prometheus-stack-grafana-xxxxxxxxxx-xxxxx   1/1     Running   0          30s

# Check services
kubectl get svc -n monitoring

# Expected output should include:
# kube-prometheus-stack-grafana       NodePort    10.x.x.x    <none>        30030:30030/TCP
# kube-prometheus-stack-prometheus    ClusterIP   10.x.x.x    <none>        9090/TCP
# kube-prometheus-stack-operator      ClusterIP   10.x.x.x    <none>        8443/TCP
```

### Access Grafana

```bash
# Get Grafana URL
kubectl get svc -n monitoring kube-prometheus-stack-grafana

# Access via NodePort
# URL: http://<node-ip>:30030
# Username: admin
# Password: admin
```

---

## Step 2: Install DCGM Exporter

DCGM (Data Center GPU Manager) Exporter collects GPU telemetry and exposes it in Prometheus format.

### Install via Helm

```bash
# Add NVIDIA repository (if not added)
helm repo add nvidia https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

# Install DCGM Exporter
helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace monitoring \
  --version 3.3.0-3.1.0 \
  --set serviceMonitor.enabled=true \
  --set serviceMonitor.namespace=monitoring \
  --set serviceMonitor.interval=15s
```

**Helm Values Explained:**
- `serviceMonitor.enabled=true`: Create ServiceMonitor for Prometheus discovery
- `serviceMonitor.namespace=monitoring`: Place ServiceMonitor in monitoring namespace
- `serviceMonitor.interval=15s`: Scrape interval for DCGM metrics

### Verify DCGM Exporter Installation

```bash
# Check DCGM Exporter DaemonSet
kubectl get daemonset -n monitoring dcgm-exporter

# Expected output:
# NAME            DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
# dcgm-exporter   1         1         1       1            1           <none>          10s

# Check DCGM Exporter pods
kubectl get pods -n monitoring -l app=dcgm-exporter

# Expected output:
# NAME                 READY   STATUS    RESTARTS   AGE
# dcgm-exporter-xxxxx  1/1     Running   0          15s

# Check ServiceMonitor
kubectl get servicemonitor -n monitoring

# Expected output should include:
# NAME                    AGE
# dcgm-exporter           10s
# kube-prometheus-stack   30s
```

### Verify DCGM Metrics

```bash
# Port-forward to DCGM Exporter
kubectl port-forward -n monitoring daemonset/dcgm-exporter 9400:9400 &

# Check metrics endpoint
curl http://localhost:9400/metrics | head -50

# Expected output should include:
# # DCGM_FI_DEV_FB_USED
# # DCGM_FI_DEV_GPU_UTIL
# # DCGM_FI_DEV_POWER_USAGE
# DCGM_FI_DEV_FB_USED{GPU="0",device="nvidia0"} 1234567890
# DCGM_FI_DEV_GPU_UTIL{GPU="0",device="nvidia0"} 45
# DCGM_FI_DEV_POWER_USAGE{GPU="0",device="nvidia0"} 120

# Kill port-forward
pkill -f "port-forward"
```

---

## Step 3: Configure Prometheus to Scrape DCGM

### Verify Prometheus ServiceMonitor Discovery

```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="dcgm-exporter")'

# Expected output should show:
# {
#   "labels": {
#     "job": "dcgm-exporter",
#     ...
#   },
#   "health": "up",
#   "lastError": "",
#   "lastScrape": "2026-07-02T18:00:00Z",
#   "lastScrapeDuration": 0.123,
#   "scrapeUrl": "http://10.x.x.x:9400/metrics"
# }

# Kill port-forward
pkill -f "port-forward"
```

### Query DCGM Metrics in Prometheus

```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &

# Query VRAM usage
curl -g 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_FB_USED' | jq

# Query GPU utilization
curl -g 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL' | jq

# Kill port-forward
pkill -f "port-forward"
```

---

## Step 4: Advanced DCGM Configuration

### Custom Helm Values for DCGM Exporter

Create a custom values file for DCGM Exporter:

```bash
cat <<EOF > dcgm-exporter-values.yaml
dcgmExporter:
  enabled: true
  image:
    repository: nvidia/dcgm-exporter
    tag: 3.3.0-3.1.0-ubuntu22.04
    pullPolicy: IfNotPresent
  
  # ServiceMonitor configuration
  serviceMonitor:
    enabled: true
    interval: 15s
    scrapeTimeout: 10s
    namespace: monitoring
    labels:
      release: kube-prometheus-stack
  
  # Resource limits
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 128Mi
  
  # Security context
  securityContext:
    capabilities:
      add:
        - SYS_ADMIN
  
  # Node selector
  nodeSelector:
    kubernetes.io/hostname: gpu-node-1
  
  # Tolerations
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
  
  # Extra arguments for metric selection
  extraArgs:
    - --families=DCGM_FI_DEV_FB_USED,DCGM_FI_DEV_GPU_UTIL,DCGM_FI_DEV_POWER_USAGE,DCGM_FI_DEV_TEMP,DCGM_FI_DEV_CLOCK_THROTTLE_REASON
EOF
```

### Upgrade DCGM Exporter with Custom Values

```bash
# Upgrade DCGM Exporter
helm upgrade dcgm-exporter nvidia/dcgm-exporter \
  --namespace monitoring \
  --version 3.3.0-3.1.0 \
  -f dcgm-exporter-values.yaml

# Verify upgrade
kubectl get pods -n monitoring -l app=dcgm-exporter
```

---

## Step 5: Critical DCGM Metrics

### DCGM_FI_DEV_FB_USED (Frame Buffer Usage)

**Field ID:** 158  
**Unit:** Bytes  
**Purpose:** Measures VRAM usage per GPU

**PromQL Query:**
```promql
# Current VRAM usage in bytes
DCGM_FI_DEV_FB_USED

# VRAM usage in GB
DCGM_FI_DEV_FB_USED / 1024^3

# VRAM usage percentage
(DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL) * 100

# VRAM usage by GPU
DCGM_FI_DEV_FB_USED{GPU="0"}
```

**Critical for Time-Slicing:** Since all pods share physical VRAM, this metric must be monitored to prevent OOM. Set alerts when usage exceeds 12GB (75% of 16GB).

### DCGM_FI_DEV_GPU_UTIL (GPU Utilization)

**Field ID:** 1003  
**Unit:** Percentage  
**Purpose:** Measures GPU compute utilization

**PromQL Query:**
```promql
# Current GPU utilization
DCGM_FI_DEV_GPU_UTIL

# Average GPU utilization over 5 minutes
avg_over_time(DCGM_FI_DEV_GPU_UTIL[5m])

# GPU utilization by GPU
DCGM_FI_DEV_GPU_UTIL{GPU="0"}

# Peak utilization in last hour
max_over_time(DCGM_FI_DEV_GPU_UTIL[1h])
```

**Critical for Time-Slicing:** High utilization (>90%) indicates the GPU is saturated. Consider reducing replica count or optimizing workloads.

### DCGM_FI_DEV_POWER_USAGE (Power Consumption)

**Field ID:** 250  
**Unit:** Milliwatts  
**Purpose:** Measures GPU power draw

**PromQL Query:**
```promql
# Current power usage in watts
DCGM_FI_DEV_POWER_USAGE / 1000

# Average power usage over 10 minutes
avg_over_time((DCGM_FI_DEV_POWER_USAGE / 1000)[10m])

# Power usage by GPU
DCGM_FI_DEV_POWER_USAGE{GPU="0"} / 1000
```

**Use Case:** Monitor for power spikes that may indicate thermal throttling or inefficient workloads.

### DCGM_FI_DEV_TEMP (GPU Temperature)

**Field ID:** 60  
**Unit:** Celsius  
**Purpose:** Measures GPU core temperature

**PromQL Query:**
```promql
# Current temperature
DCGM_FI_DEV_TEMP

# Maximum temperature in last hour
max_over_time(DCGM_FI_DEV_TEMP[1h])

# Temperature by GPU
DCGM_FI_DEV_TEMP{GPU="0"}
```

**Alert Threshold:** Alert when temperature exceeds 85°C to prevent thermal throttling.

### DCGM_FI_DEV_CLOCK_THROTTLE_REASON (Clock Throttle Reasons)

**Field ID:** 78  
**Unit:** Bitmask  
**Purpose:** Indicates why GPU clock is being throttled

**PromQL Query:**
```promql
# Throttle reasons
DCGM_FI_DEV_CLOCK_THROTTLE_REASON

# Check if any throttling is occurring
DCGM_FI_DEV_CLOCK_THROTTLE_REASON > 0
```

**Bitmask Values:**
- 0x01: GPU idle
- 0x02: Applications clocks limited
- 0x04: SW power cap
- 0x08: HW slowdown (thermal)
- 0x10: HW thermal slowdown
- 0x20: HW power brake slowdown

---

## Step 6: Per-Pod GPU Metrics

### Challenge: DCGM Does Not Attribute Metrics to Pods

DCGM Exporter provides GPU-level metrics, not pod-level metrics. However, we can correlate GPU usage with pods using the following strategies:

#### Strategy 1: Use cAdvisor Metrics for System RAM

cAdvisor (included in kube-prometheus-stack) provides per-pod container memory metrics:

```promql
# Container memory usage
container_memory_usage_bytes{namespace="ml-workloads"}

# Container memory usage by pod
container_memory_usage_bytes{namespace="ml-workloads", pod="embedding-service-xxxxx"}

# Container memory usage in GB
container_memory_usage_bytes{namespace="ml-workloads"} / 1024^3
```

#### Strategy 2: Use Kubernetes Node Exporter for System Metrics

Node Exporter provides system-level metrics:

```promql
# System memory usage
node_memory_MemAvailable_bytes

# System CPU usage
rate(node_cpu_seconds_total[5m])
```

#### Strategy 3: Custom Metrics from Application

Embed memory stats in application health endpoints (as shown in `03-workloads-and-memory.md`):

```python
@app.get("/health")
async def health():
    stats = get_memory_stats(device)
    return {
        "status": "healthy",
        "memory_stats": stats
    }
```

Then scrape these endpoints with Prometheus:

```yaml
# PodMonitor for custom metrics
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: ml-workloads
  namespace: monitoring
spec:
  selector:
    matchLabels:
      workload-type: gpu-inference
  podMetricsEndpoints:
  - port: http
    path: /health
    interval: 30s
```

---

## Step 7: Grafana Dashboard Configuration

### Import NVIDIA GPU Dashboard

Grafana includes a pre-built NVIDIA GPU dashboard:

1. Access Grafana: `http://<node-ip>:30030`
2. Login with `admin/admin`
3. Navigate to Dashboards → Import
4. Import dashboard ID: 12239 (NVIDIA DCGM Exporter Dashboard)
5. Select Prometheus data source

### Custom Dashboard for Time-Sliced Workloads

Create a custom dashboard JSON:

```json
{
  "dashboard": {
    "title": "GPU Time-Slicing Monitoring",
    "panels": [
      {
        "title": "VRAM Usage (GB)",
        "targets": [
          {
            "expr": "DCGM_FI_DEV_FB_USED{GPU=\"0\"} / 1024^3",
            "legendFormat": "VRAM Used"
          },
          {
            "expr": "DCGM_FI_DEV_FB_TOTAL{GPU=\"0\"} / 1024^3",
            "legendFormat": "VRAM Total"
          }
        ],
        "type": "graph"
      },
      {
        "title": "GPU Utilization (%)",
        "targets": [
          {
            "expr": "DCGM_FI_DEV_GPU_UTIL{GPU=\"0\"}",
            "legendFormat": "GPU Util"
          }
        ],
        "type": "graph"
      },
      {
        "title": "GPU Temperature (°C)",
        "targets": [
          {
            "expr": "DCGM_FI_DEV_TEMP{GPU=\"0\"}",
            "legendFormat": "Temperature"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Power Usage (W)",
        "targets": [
          {
            "expr": "DCGM_FI_DEV_POWER_USAGE{GPU=\"0\"} / 1000",
            "legendFormat": "Power"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Pod Memory Usage (GB)",
        "targets": [
          {
            "expr": "container_memory_usage_bytes{namespace=\"ml-workloads\"} / 1024^3",
            "legendFormat": "{{pod}}"
          }
        ],
        "type": "graph"
      }
    ]
  }
}
```

Import this dashboard via Grafana UI.

---

## Step 8: Alerting Rules

### Create Alerting Rules

Create a ConfigMap for custom alerting rules:

```bash
cat <<EOF > gpu-alerting-rules.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gpu-alerting-rules
  namespace: monitoring
data:
  gpu-alerts.yaml: |
    groups:
    - name: gpu-time-slicing
      interval: 30s
      rules:
      # VRAM Usage Alert
      - alert: HighVRAMUsage
        expr: (DCGM_FI_DEV_FB_USED{GPU="0"} / DCGM_FI_DEV_FB_TOTAL{GPU="0"}) * 100 > 75
        for: 5m
        labels:
          severity: warning
          component: gpu
        annotations:
          summary: "GPU VRAM usage exceeds 75%"
          description: "GPU {{ $labels.GPU }} VRAM usage is {{ $value }}%"

      - alert: CriticalVRAMUsage
        expr: (DCGM_FI_DEV_FB_USED{GPU="0"} / DCGM_FI_DEV_FB_TOTAL{GPU="0"}) * 100 > 90
        for: 2m
        labels:
          severity: critical
          component: gpu
        annotations:
          summary: "GPU VRAM usage exceeds 90%"
          description: "GPU {{ $labels.GPU }} VRAM usage is {{ $value }}%. Immediate action required."

      # GPU Utilization Alert
      - alert: GPUSaturation
        expr: avg_over_time(DCGM_FI_DEV_GPU_UTIL{GPU="0"}[5m]) > 95
        for: 10m
        labels:
          severity: warning
          component: gpu
        annotations:
          summary: "GPU utilization > 95% for 10 minutes"
          description: "GPU {{ $labels.GPU }} is saturated at {{ $value }}% utilization"

      # Temperature Alert
      - alert: HighGPUTemperature
        expr: DCGM_FI_DEV_TEMP{GPU="0"} > 85
        for: 5m
        labels:
          severity: warning
          component: gpu
        annotations:
          summary: "GPU temperature exceeds 85°C"
          description: "GPU {{ $labels.GPU }} temperature is {{ $value }}°C"

      # Throttling Alert
      - alert: GPUThrottling
        expr: DCGM_FI_DEV_CLOCK_THROTTLE_REASON{GPU="0"} > 0
        for: 1m
        labels:
          severity: warning
          component: gpu
        annotations:
          summary: "GPU clock throttling detected"
          description: "GPU {{ $labels.GPU }} is being throttled. Reason: {{ $value }}"

      # Pod Memory Alert
      - alert: HighPodMemoryUsage
        expr: container_memory_usage_bytes{namespace="ml-workloads"} / container_spec_memory_limit_bytes{namespace="ml-workloads"} > 0.8
        for: 5m
        labels:
          severity: warning
          component: pod
        annotations:
          summary: "Pod memory usage exceeds 80% of limit"
          description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is using {{ $value }}% of memory limit"
EOF

# Apply the ConfigMap
kubectl apply -f gpu-alerting-rules.yaml
```

### Update Prometheus to Use Custom Rules

```bash
# Edit kube-prometheus-stack to include custom rules
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.additionalRuleSelectorLabels.rulegroup=gpu-alerting \
  --set-file prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false
```

Alternatively, create a PrometheusRule custom resource:

```bash
cat <<EOF > prometheus-rule-gpu.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gpu-alerting-rules
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
  - name: gpu-time-slicing
    interval: 30s
    rules:
    - alert: HighVRAMUsage
      expr: (DCGM_FI_DEV_FB_USED{GPU="0"} / DCGM_FI_DEV_FB_TOTAL{GPU="0"}) * 100 > 75
      for: 5m
      labels:
        severity: warning
        component: gpu
      annotations:
        summary: "GPU VRAM usage exceeds 75%"
        description: "GPU {{ $labels.GPU }} VRAM usage is {{ $value }}%"
EOF

kubectl apply -f prometheus-rule-gpu.yaml
```

---

## Verification Checklist

### DCGM Exporter Verification

```bash
# 1. DCGM Exporter DaemonSet is running
kubectl get daemonset -n monitoring dcgm-exporter
# Expected: DESIRED=1, CURRENT=1, READY=1

# 2. DCGM Exporter pod is running
kubectl get pods -n monitoring -l app=dcgm-exporter
# Expected: 1/1 Running

# 3. DCGM metrics are accessible
kubectl port-forward -n monitoring daemonset/dcgm-exporter 9400:9400 &
curl http://localhost:9400/metrics | grep DCGM_FI_DEV_FB_USED
pkill -f "port-forward"
# Expected: Metric values present
```

### Prometheus Verification

```bash
# 4. Prometheus is scraping DCGM metrics
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -g 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_FB_USED' | jq '.data.result'
pkill -f "port-forward"
# Expected: Metric values returned

# 5. ServiceMonitor is configured
kubectl get servicemonitor -n monitoring dcgm-exporter
# Expected: ServiceMonitor exists
```

### Grafana Verification

```bash
# 6. Grafana is accessible
kubectl get svc -n monitoring kube-prometheus-stack-grafana
# Expected: NodePort 30030

# 7. Grafana dashboard shows GPU metrics
# Access http://<node-ip>:30030 and verify dashboard displays data
```

### Alerting Verification

```bash
# 8. PrometheusRule is created
kubectl get prometheusrule -n monitoring gpu-alerting-rules
# Expected: Rule exists

# 9. Alerts are evaluated
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -g 'http://localhost:9090/api/v1/rules' | jq '.data.groups[] | select(.name=="gpu-time-slicing")'
pkill -f "port-forward"
# Expected: Alert rules listed
```

---

## Troubleshooting

### Issue: DCGM Exporter pod fails to start

**Symptom:** DCGM Exporter pod has CrashLoopBackOff status.

**Solution:**
```bash
# Check pod logs
kubectl logs -n monitoring -l app=dcgm-exporter

# Common error: "Failed to initialize DCGM"
# Solution: Verify NVIDIA driver is loaded
nvidia-smi

# Common error: "Permission denied"
# Solution: Verify SYS_ADMIN capability is set
kubectl get daemonset -n monitoring dcgm-exporter -o yaml | grep -A 5 capabilities
```

### Issue: Prometheus not scraping DCGM metrics

**Symptom:** Prometheus targets show DCGM Exporter as "down".

**Solution:**
```bash
# Check ServiceMonitor configuration
kubectl get servicemonitor -n monitoring dcgm-exporter -o yaml

# Verify namespace matches
kubectl get servicemonitor -n monitoring dcgm-exporter -o yaml | grep namespace

# Verify Prometheus ServiceMonitor selector
kubectl get prometheus -n monitoring -o yaml | grep serviceMonitorSelector

# If selector is too restrictive, update:
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

### Issue: No metrics in Grafana dashboard

**Symptom:** Grafana dashboard shows "No data".

**Solution:**
```bash
# Verify Prometheus data source in Grafana
# Access Grafana → Configuration → Data Sources → Prometheus
# Verify URL: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090

# Test query in Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -g 'http://localhost:9090/api/v1/query?query=up' | jq
pkill -f "port-forward"

# If Prometheus returns data, issue is Grafana configuration
# If Prometheus returns no data, issue is metric scraping
```

### Issue: Alerts not firing

**Symptom:** Alert conditions are met but alerts are not firing.

**Solution:**
```bash
# Check alert rules are loaded
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -g 'http://localhost:9090/api/v1/rules' | jq '.data.groups[] | select(.name=="gpu-time-slicing")'
pkill -f "port-forward"

# Check alert state
curl -g 'http://localhost:9090/api/v1/alerts' | jq '.data.alerts[] | select(.labels.alertname=="HighVRAMUsage")'

# Verify Alertmanager is configured
kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager
```

---

## Advanced Configuration

### Custom Metric Collection

To collect additional DCGM metrics, modify the extraArgs:

```yaml
# dcgm-exporter-values.yaml
dcgmExporter:
  extraArgs:
    - --families=DCGM_FI_DEV_FB_USED,DCGM_FI_DEV_GPU_UTIL,DCGM_FI_DEV_POWER_USAGE,DCGM_FI_DEV_TEMP,DCGM_FI_DEV_CLOCK_THROTTLE_REASON,DCGM_FI_DEV_PCIE_REPLAY_COUNTER,DCGM_FI_DEV_XID_ERRORS
```

### Multiple GPU Nodes

For multi-node clusters, adjust the DaemonSet:

```yaml
# dcgm-exporter-values.yaml
dcgmExporter:
  nodeSelector:
    # Remove specific node selector to run on all GPU nodes
    hardware-type: gpu-node
```

### Long-Term Metric Storage

For long-term retention, configure Prometheus storage:

```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.retentionSize=50GB \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=local-path
```

---

## Summary

With observability configured, you now have:
- **DCGM Exporter** collecting GPU telemetry every 15 seconds
- **Prometheus** storing and querying metrics
- **Grafana** visualizing GPU utilization, VRAM usage, temperature, and power
- **Alerting rules** notifying on high VRAM usage, GPU saturation, and thermal issues

This completes the core GPU Time-Slicing architecture. All foundational components are now operational:
1. Infrastructure (k3s + Docker + NVIDIA Container Toolkit)
2. GPU Time-Slicing (Device Plugin + ConfigMap)
3. Workloads (FastAPI + PyTorch with memory management)
4. Observability (DCGM + Prometheus + Grafana)

For production readiness and advanced operations, proceed to:
- **GitOps and CI/CD** (`05-gitops-cicd.md`) — Automated deployments with GitHub Actions and ArgoCD
- **FinOps Analysis** (`06-finops-roi-analysis.md`) — Cost-benefit analysis and ROI calculations
- **Performance Benchmarks** (`07-performance-benchmarks.md`) — Load testing with Locust
- **Power Optimization** (`08-hardware-power-optimization.md`) — GreenOps power capping strategies
- **Security Hardening** (`09-security-and-network-isolation.md`) — NetworkPolicy and RBAC
- **Disaster Recovery** (`10-disaster-recovery.md`) — Velero backups and MinIO storage
