# GPU Time-Slicing Configuration

**Component:** NVIDIA Device Plugin with Time-Slicing  
**Objective:** Present 1 physical RTX 5070 Ti (16GB) as 4 logical GPU replicas  
**Namespace:** gpu-infrastructure  

---

## Prerequisites

Verify the successful completion of the infrastructure setup:

```bash
# Verify k3s is running
kubectl get nodes

# Verify Helm repositories are added
helm repo list

# Verify namespaces exist
kubectl get namespaces | grep gpu-infrastructure
```

---

## Step 1: Time-Slicing vs. MIG

Consumer GPUs (e.g., RTX 5070 Ti) lack hardware-level MIG (Multi-Instance GPU). Time-Slicing is a software-based multiplexing technique that:
- Divides GPU compute time into temporal slices (10ms by default).
- Over-subscribes the physical GPU, exposing multiple logical replicas to the Kubernetes scheduler.
- Enables concurrent pod execution on a single physical GPU.

### Configuration Parameters

| **Parameter** | **Value** | **Purpose** |
|---------------|-----------|-------------|
| `migStrategy` | `none` | Disables MIG (required for consumer GPUs) |
| `replicas` | `4` | Number of logical GPU replicas |
| `renameByDefault` | `false` | Retains standard `nvidia.com/gpu` nomenclature |
| `failRequestsGreaterThanOne` | `true` | Prevents pods from consuming >1 slice (1:1 mapping) |
| `maxShares` | `4` | Maximum allowable replication factor |

---

## Step 2: Deploy NVIDIA Device Plugin

Install the Device Plugin via Helm, enforcing the `volumeMount` strategy required by containerd/Docker runtimes.

```bash
helm install nvidia-device-plugin nvidia/k8s-device-plugin \
  --namespace gpu-infrastructure \
  --version v0.15.0 \
  --set deviceListStrategy=volumeMount \
  --set migStrategy=none \
  --set gds.enabled=false \
  --set mofed.enabled=false
```

Verify deployment:

```bash
kubectl get daemonset -n gpu-infrastructure
kubectl get pods -n gpu-infrastructure -l name=nvidia-device-plugin-ds
```

At this stage, node allocatable resources will show 1 GPU because the time-slicing configuration is not yet applied:

```bash
kubectl describe node gpu-node-1 | grep -A 15 "Allocatable"
```

---

## Step 3: Define Time-Slicing ConfigMap

Create the ConfigMap that defines the over-subscription rules.

```bash
cat <<EOF > time-slicing-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin-config
  namespace: gpu-infrastructure
data:
  config.yaml: |
    version: v1
    sharing:
      timeSlicing:
        renameByDefault: false
        failRequestsGreaterThanOne: true
        maxShares: 4
        resources:
          - name: nvidia.com/gpu
            replicas: 4
EOF

kubectl apply -f time-slicing-configmap.yaml
kubectl get configmap -n gpu-infrastructure nvidia-device-plugin-config
```

---

## Step 4: Apply Configuration

The Device Plugin requires a restart to mount the new configuration file.

```bash
kubectl delete pod -n gpu-infrastructure -l name=nvidia-device-plugin-ds
kubectl get pods -n gpu-infrastructure -l name=nvidia-device-plugin-ds -w
```

---

## Step 5: Verify Logical Allocation

Check the plugin logs for the Time-Slicing initialization string:

```bash
kubectl logs -n gpu-infrastructure -l name=nvidia-device-plugin-ds --tail=50
```

Verify the Kubernetes scheduler now recognizes 4 logical replicas:

```bash
kubectl describe node gpu-node-1 | grep -A 15 "Allocatable"
```

*Note: For Time-Slicing, both `Capacity` and `Allocatable` must report `nvidia.com/gpu: 4`.*

---

## Step 6: Functional Concurrency Test

Deploy a DaemonSet or multiple pods to ensure concurrent GPU access.

```bash
cat <<EOF > multi-gpu-test.yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test-1
  namespace: gpu-infrastructure
spec:
  containers:
  - name: gpu-test
    image: nvidia/cuda:12.1.0-base-ubuntu22.04
    command: ["sleep", "300"]
    resources:
      limits:
        nvidia.com/gpu: 1
---
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test-2
  namespace: gpu-infrastructure
spec:
  containers:
  - name: gpu-test
    image: nvidia/cuda:12.1.0-base-ubuntu22.04
    command: ["sleep", "300"]
    resources:
      limits:
        nvidia.com/gpu: 1
---
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test-3
  namespace: gpu-infrastructure
spec:
  containers:
  - name: gpu-test
    image: nvidia/cuda:12.1.0-base-ubuntu22.04
    command: ["sleep", "300"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

kubectl apply -f multi-gpu-test.yaml
```

Ensure all three pods reach the `Running` state concurrently:

```bash
kubectl get pods -n gpu-infrastructure
```

Verify GPU context from within the containers:

```bash
kubectl exec -n gpu-infrastructure gpu-test-1 -- nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader
kubectl exec -n gpu-infrastructure gpu-test-2 -- nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader
kubectl exec -n gpu-infrastructure gpu-test-3 -- nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader
```

Clean up:

```bash
kubectl delete -f multi-gpu-test.yaml
```

---

## Troubleshooting

### Scheduler Rejects GPU Requests (nvidia.com/gpu: 1)
**Condition:** `kubectl describe node` reports `nvidia.com/gpu: 1` post-configuration.
**Resolution:** The pod failed to load the ConfigMap. Verify the ConfigMap exists in `gpu-infrastructure` and restart the daemonset pod.

### Pods Stuck in ContainerCreating
**Condition:** Pods requesting GPU hang indefinitely. `kubectl describe pod` shows "Insufficient nvidia.com/gpu".
**Resolution:** Time-Slicing is not active. Check the Device Plugin logs for parsing errors in `config.yaml`.

### Device Plugin CrashLoopBackOff
**Condition:** The plugin fails to start.
**Resolution:** Validate that the NVIDIA kernel driver is loaded (`nvidia-smi` on host) and the Container Toolkit default runtime is correctly mapped to containerd.

---

## Next Steps

Proceed to `03-workloads-and-memory.md` to deploy the PyTorch services and implement VRAM fractioning for OOM protection.
