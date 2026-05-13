# 20. Event-Driven Autoscaling (KEDA)

While Time-Slicing allows us to pack multiple pods onto a single GPU, we still need a way to automatically scale the number of pods up or down based on actual workload demand, rather than static CPU/Memory metrics.

To achieve this, we use **KEDA (Kubernetes Event-driven Autoscaling)**.

---

## 1. Why KEDA?

Standard Kubernetes Horizontal Pod Autoscaler (HPA) typically scales based on CPU or Memory utilization. However, for ML workloads:
- GPU memory is statically allocated (e.g. our 3.2GB slices) and doesn't fluctuate like RAM.
- GPU Compute (CUDA cores) utilization is hard for standard HPA to track accurately.
- Background tasks (like our `background-worker`) process queues in Redis. The best indicator of load is the **length of the queue**, not the CPU usage.

KEDA solves this by scaling pods based on external metrics, such as the length of a Redis list.

## 2. The Configuration

In our deployment, KEDA is configured to monitor the Redis queue length for background ML tasks.

```yaml
# k8s/15-keda-autoscaler.yaml (Excerpt)
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: background-worker-scaler
  namespace: workloads
spec:
  scaleTargetRef:
    name: background-worker
  minReplicaCount: 1
  maxReplicaCount: 10
  triggers:
  - type: redis
    metadata:
      address: redis-master.workloads.svc.cluster.local:6379
      listName: ml_task_queue
      listLength: "50" # Scale up if queue has more than 50 items
```

## 3. How It Operates

1. **Idle State**: If the `ml_task_queue` in Redis is empty, KEDA scales the `background-worker` deployment down to `minReplicaCount` (1).
2. **Traffic Spike**: A user submits 500 video generation requests. They land in the Redis queue instantly.
3. **Scaling Action**: KEDA detects the queue length is 500 (which is > 50). It instructs Kubernetes to spin up more `background-worker` pods, up to the `maxReplicaCount` (10).
4. **Distribution**: These new pods land on available GPU slices across the cluster. The tasks are processed 10x faster.
5. **Scale Down**: Once the queue is depleted, KEDA gracefully scales the workers back down to 1, freeing up GPU slices for other services like `vision-service` or `embedding-service`.
