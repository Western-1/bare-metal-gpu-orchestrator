# Event-Driven Autoscaling (KEDA)

**Component:** Kubernetes Event-driven Autoscaling (KEDA)  
**Objective:** Dynamic Time-Slice workload provisioning via external metric triggers  
**Trigger Source:** Redis Queue Depth  

---

## 1. Architectural Justification

Standard Kubernetes Horizontal Pod Autoscalers (HPA) rely fundamentally on continuous CPU/Memory telemetry. For GPU-bound ML inference workloads:
- GPU VRAM reservations are statically bounded (e.g., rigid 3.2GB slices) and do not linearly correlate with ingress volume.
- Standard HPA controllers lack native integration with CUDA SM utilization metrics.
- Asynchronous pipeline load (e.g., `background-worker` processing) is best measured via broker queue depth, an external metric invisible to native HPAs.

**KEDA** bridges this gap by extending the Kubernetes metrics server, allowing deployments to autoscale based directly on state representations from external brokers (e.g., Redis List Lengths).

---

## 2. KEDA ScaledObject Configuration

The infrastructure leverages a `ScaledObject` CRD to map the `background-worker` deployment target to a specific Redis list depth threshold.

```yaml
# manifests/workloads/keda-autoscaler.yaml (Excerpt)
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
      listLength: "50" 
```

### Trigger Mechanics
- **Metric Mapping:** `listLength: "50"` dictates that KEDA provisions 1 replica per 50 pending queue items.

---

## 3. Operational Lifecycle

1. **Idle State:** When the Redis list `ml_task_queue` contains zero elements, KEDA aggressively scales the deployment down to the `minReplicaCount` (`1`), liberating fractional GPU compute for synchronous HTTP services (e.g., `embedding-service`).
2. **Ingress Spike:** An external system enqueues 500 asynchronous generation payloads to Redis.
3. **Scale Out:** KEDA's polling loop observes a depth of 500. Calculating against the `50` target length, the controller immediately instructs the Kubernetes scheduler to provision up to `maxReplicaCount` (`10`).
4. **Saturation:** Ten worker pods acquire available Time-Slices across the node pool and drain the queue in parallel.
5. **Scale In:** As the list length falls, KEDA executes a controlled downscale, reclaiming VRAM partitions.

---

## Next Steps

Proceed to `21-ray-distributed-ml.md` to configure the KubeRay operator for distributed multi-node inference topologies.
