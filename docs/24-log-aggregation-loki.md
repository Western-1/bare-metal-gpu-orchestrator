# Centralized Log Aggregation (PLG Stack)

**Component:** Promtail, Loki, Grafana (PLG)  
**Objective:** Centralized, highly-available stdout/stderr telemetry aggregation  
**Storage Backend:** Local Disk / MinIO  

---

## 1. Architectural Need

Executing workloads dynamically across a cluster (e.g., KEDA scaling `background-worker` from 1 to 10 replicas) renders native tools like `kubectl logs` obsolete for debugging multi-pod faults.

A unified logging plane is strictly required to ingest, index, and query application stdout streams. We deploy the lightweight PLG stack over ElasticSearch to minimize overhead on bare-metal GPU nodes.

---

## 2. Component Topology

- **Promtail:** DaemonSet agent deployed on every node. Mounts `/var/log/containers/`, scrapes container output, and forwards payloads via gRPC.
- **Loki:** Centralized log indexing engine. Horizontally scalable and S3-compatible.
- **Grafana:** Query interface utilizing LogQL (integrated with our existing Prometheus dashboarding setup).

---

## 3. Installation via Helm

Add the official Grafana repository:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### Loki Deployment

Deploy Loki in single-binary mode for lightweight operations.

```yaml
# loki-values.yaml
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: 'filesystem'
singleBinary:
  replicas: 1
```

```bash
helm install loki grafana/loki \
  --namespace monitoring \
  -f loki-values.yaml \
  --version 5.41.4
```

### Promtail Deployment

Deploy Promtail to scrape all node logs.

```bash
helm install promtail grafana/promtail \
  --namespace monitoring \
  --set "config.clients[0].url=http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push" \
  --version 6.15.3
```

---

## 4. Grafana Integration and LogQL

1. Navigate to the Grafana UI (`http://<node-ip>:3000`).
2. Navigate to **Connections -> Data Sources -> Add data source**.
3. Select **Loki**.
4. URL: `http://loki.monitoring.svc.cluster.local:3100`
5. Click **Save & Test**.

### Querying Logs (LogQL Examples)

Navigate to the **Explore** tab in Grafana to execute LogQL queries:

**Filter by Application:**
```logql
{app="embedding-service"}
```

**Filter by Namespace and Search for Exceptions:**
```logql
{namespace="ml-workloads"} |= "Exception"
```

**Parse JSON Payload and Filter Latency:**
```logql
{app="vision-service"} | json | latency_ms > 500
```

---

## 5. Log Rotation and Eviction Policy

Unchecked container logs will exhaust host storage. Enforce log rotation at the Docker daemon level.

```bash
# Update Docker Daemon Config on the host
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF
sudo systemctl restart docker
```

---

## Next Steps

Proceed to `25-storage-io-optimization.md` to configure hardware RAID arrays for rapid model loading.
