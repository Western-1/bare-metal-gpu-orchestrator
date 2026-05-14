# Distributed ML Processing (KubeRay)

**Component:** Ray & KubeRay Operator  
**Objective:** Distributed execution for heavy ML workloads (e.g., distributed training, batch inference)  
**Architecture:** Master/Worker Topology with GPU fractional allocation  

---

## 1. Architectural Justification

While Time-Slicing efficiently handles low-latency asynchronous/synchronous inference endpoints, heavy compute tasks (e.g., LLM fine-tuning, 100GB batch vectorization) exceed the boundary of a single node or a fractional GPU slice.

To orchestrate distributed compute horizontally, the architecture leverages **Ray** via the **KubeRay** Kubernetes Operator, converting the cluster into a unified execution pool for Data Science workloads.

---

## 2. KubeRay Deployment Configuration

The repository deploys the KubeRay Operator alongside a specific `RayCluster` CRD.

```yaml
# manifests/workloads/ray-cluster.yaml (Excerpt)
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: devops-ray-cluster
  namespace: workloads
spec:
  headGroupSpec:
    replicas: 1
    template:
      spec:
        containers:
        - name: ray-head
          image: rayproject/ray:latest-gpu
          resources:
            requests:
              cpu: "2"
              memory: "8Gi"
  workerGroupSpecs:
  - replicas: 3
    groupName: gpu-workers
    template:
      spec:
        containers:
        - name: ray-worker
          image: rayproject/ray:latest-gpu
          resources:
            limits:
              nvidia.com/gpu: 1
```

---

## 3. Distributed Execution Mechanics

1. **Head Node (Control Plane):** The Ray Head Node operates strictly as a metadata scheduler and cluster manager. It does not execute tensor operations or consume GPU limits.
2. **Worker Nodes (Data Plane):** The `gpu-workers` replica set provisions execution pods. Leveraging the underlying Time-Slicing Device Plugin, these pods schedule densely onto the physical bare-metal hardware.
3. **Execution Routing:** Python scripts submitted to the Head node are automatically serialized. The Ray scheduler partitions the dataset, distributes object references, executes tensor operations in parallel across the Time-Sliced worker pool, and aggregates the distributed object store results.

---

## 4. Job Submission Protocol

Expose the Ray Dashboard and Ray Client API port to submit localized training scripts to the remote cluster:

```bash
# 1. Establish API tunnel
kubectl port-forward svc/devops-ray-cluster-head-svc 8265:8265 -n workloads

# 2. Submit remote job via Ray CLI
ray job submit \
  --address="http://localhost:8265" \
  --working-dir ./scripts \
  -- python train_distributed.py
```

**Telemetry:** 
Monitor actor distribution, cluster utilization, and worker node health natively via the Ray Dashboard at `http://localhost:8265`.
