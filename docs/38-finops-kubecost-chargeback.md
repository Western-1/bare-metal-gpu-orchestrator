# FinOps Chargeback (Kubecost)

**Component:** Kubecost / OpenCost  
**Objective:** Attribute granular GPU hardware costs to specific engineering teams or microservices  
**Integration:** Prometheus Metrics + Cloud Billing APIs  

---

## 1. The Cost Attribution Blindspot

In a multi-tenant GPU Time-Slicing cluster, calculating ROI (`06-finops-roi-analysis.md`) at the hardware level is straightforward (Hardware Cost / Total Lifespan). 

However, attributing that cost internally is complex. If Team A runs an `embedding-service` (1 GPU Slice) and Team B runs a Ray distributed training job (12 GPU Slices), Finance requires a mechanism to generate internal chargeback reports based on exact consumption.

---

## 2. Kubecost Architecture

**Kubecost** (built on the OpenCost CNCF standard) integrates with Prometheus to analyze resource requests, limits, and actual utilization. It cross-references this telemetry against a configured pricing sheet (or cloud billing APIs) to calculate daily/monthly spend per Namespace, Deployment, or Pod.

### Deployment

Deploy Kubecost via Helm, pointing it to the existing Prometheus installation.

```bash
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm repo update

helm install kubecost kubecost/cost-analyzer \
    --namespace kubecost \
    --create-namespace \
    --set global.prometheus.fqdn=http://prometheus-server.monitoring.svc.cluster.local \
    --set global.prometheus.enabled=false
```

---

## 3. Custom Pricing Configuration for Bare-Metal

Because this architecture utilizes amortized bare-metal hardware rather than hourly cloud instances, the pricing models must be defined manually via a `custom-pricing.yaml` config map.

```yaml
# custom-pricing.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-pricing
  namespace: kubecost
data:
  pricing: |
    {
      "CPU": "0.010",
      "RAM": "0.005",
      "GPU": "0.350",   # Amortized hourly cost of an RTX 5070 Ti slice
      "storage": "0.001"
    }
```

Apply the config and restart the Kubecost pods. Kubecost will now assign a hardware cost of $0.35 per hour to any pod holding a `nvidia.com/gpu` Time-Slice reservation.

---

## 4. Generating Chargeback Reports

1. Port-forward the Kubecost UI (`kubectl port-forward svc/kubecost-cost-analyzer 9090:9090 -n kubecost`).
2. Navigate to **Allocation**.
3. Group by **Namespace**.

### Resulting Output
- **Namespace `team-search`:** $25.20 / month (Consumed 1 Replica for 72 hours).
- **Namespace `team-research`:** $1,250.00 / month (Consumed 12 Replicas for 300 hours via KubeRay).

This granular telemetry enables precise internal FinOps billing, justifying further bare-metal hardware acquisitions based on empirical departmental usage.

---

## Next Steps

Proceed to `39-multi-cluster-federation.md` to deploy workloads across geographically distributed datacenters.
