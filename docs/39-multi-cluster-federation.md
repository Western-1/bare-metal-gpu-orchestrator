# Multi-Cluster Federation (Karmada)

**Component:** Kubernetes Federation  
**Objective:** Orchestrate ML workloads across geographically dispersed datacenters  
**Architecture:** Karmada Control Plane  

---

## 1. The Multi-Region Scaling Challenge

As AI deployments reach global scale, confining infrastructure to a single datacenter introduces critical latency and availability risks.
- **Latency:** Serving European users from a US-East GPU cluster incurs 100ms+ physical network latency before inference even begins.
- **Data Sovereignty:** GDPR requires certain data processing to remain strictly within EU borders.
- **Redundancy:** An entire datacenter outage (power loss, severed fiber) necessitates cross-regional failover.

Managing separate k3s clusters manually via distinct `kubeconfig` files and ArgoCD instances leads to configuration drift and operational fragmentation.

---

## 2. Karmada Federation Architecture

**Karmada** (Kubernetes Armada) provides centralized multi-cloud and multi-cluster management. It exposes a unified API endpoint that looks and acts like a standard Kubernetes cluster.

### Mechanism
1. The DevOps engineer submits standard Kubernetes manifests (Deployments, Services) to the central Karmada Control Plane.
2. Karmada analyzes a `PropagationPolicy` CRD.
3. Karmada calculates cluster capacities and distributes the workloads to the target member clusters (e.g., `us-east-cluster`, `eu-west-cluster`).
4. Resource status is aggregated back to the central plane.

---

## 3. Propagation Policies

Instead of deploying to a namespace, you define a `PropagationPolicy` to dynamically instruct Karmada on how to distribute the GPU workloads.

### Scenario A: Geographically Distributed Serving (Active/Active)
Deploy the Embedding API to both US and EU clusters, demanding 2 GPU Time-Slices in each.

```yaml
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: global-embedding-policy
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      name: embedding-service
  placement:
    clusterAffinity:
      clusterNames:
        - us-east-cluster
        - eu-west-cluster
    replicaScheduling:
      replicaDivisionPreference: Strict
      replicaWeightPreference:
        staticWeightList:
          - targetCluster:
              clusterNames: ["us-east-cluster"]
            weight: 1
          - targetCluster:
              clusterNames: ["eu-west-cluster"]
            weight: 1
```

### Scenario B: Overflow/Bursting
Attempt to schedule heavy KubeRay training jobs in the primary on-premise Bare-Metal cluster. If resources (GPU slices) are exhausted, overflow the pending pods dynamically to a secondary Cloud (AWS/GCP) cluster.

```yaml
# Overflow Policy Excerpt
  placement:
    replicaScheduling:
      replicaSchedulingType: Divided
      replicaDivisionPreference: Aggregated
    clusterAffinity:
      clusterNames:
        - bare-metal-hq
        - aws-gpu-overflow
```

---

## 4. Multi-Cluster Ingress

For inbound HTTP traffic routing, deploy an external Global Server Load Balancer (GSLB) or utilize cloud provider Anycast IPs (e.g., Cloudflare, AWS Global Accelerator) to route clients to the geographically closest healthy cluster ingress.

---

## Next Steps

Proceed to `40-automated-model-evaluation.md` to establish continuous LLM quality pipelines.
