# 21. Distributed ML Processing (KubeRay)

For standard inference (like generating a text embedding), a single Time-Sliced GPU partition is sufficient. However, for massive ML workloads—like fine-tuning a Large Language Model (LLM) or processing a 100-gigabyte dataset—a single GPU partition, or even a single full GPU, is not enough.

To solve this, we use **Ray** (specifically **KubeRay** for Kubernetes).

---

## 1. What is Ray?

Ray is a framework for scaling AI and Python applications. It allows you to write Python code once and execute it seamlessly across hundreds of machines and GPUs in a cluster. 

By deploying KubeRay, we transform our Kubernetes cluster into a massive, unified supercomputer for Data Scientists.

## 2. The KubeRay Deployment

We deploy the Ray Operator and a `RayCluster` Custom Resource Definition (CRD).

```yaml
# k8s/16-ray-cluster.yaml (Excerpt)
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

## 3. How It Works in Practice

1. **The Head Node**: The Ray Head node acts as the master scheduler. It doesn't perform heavy ML work; it just orchestrates tasks.
2. **The Worker Nodes**: We deploy multiple Ray Worker pods. Because our cluster uses GPU Time-Slicing, these workers can be packed tightly onto our physical GPUs.
3. **Task Distribution**: A Data Scientist submits a training script to the Head node. Ray automatically breaks the dataset into chunks, sends the chunks to the Worker pods, executes the training in parallel across multiple GPU slices, and aggregates the results back.

## 4. Submitting a Ray Job

To submit a Python script to the Ray cluster:

```bash
# Port-forward the Ray Dashboard and API
kubectl port-forward svc/devops-ray-cluster-head-svc 8265:8265 -n workloads

# Submit the job
ray job submit --address="http://localhost:8265" --working-dir ./scripts -- python train_distributed.py
```

You can view the progress, resource utilization, and logs of your distributed job by opening the Ray Dashboard at `http://localhost:8265`.
