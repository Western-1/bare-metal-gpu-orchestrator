# 14. Advanced Multi-GPU Topologies

This guide covers advanced configurations for scaling beyond a single consumer GPU to heavy multi-GPU servers (e.g., a node with 4x RTX 5090s) and complex workload distribution.

---

## 1. Arbitrary Time-Slicing

In our base architecture, we configured `replicas: 4` for the GPU Time-Slicing ConfigMap. **This is not a hard hardware limit.** 

Because Time-Slicing is a purely temporal, software-based multiplexer, you can arbitrarily configure `replicas: 10`, `20`, or `100`. 

### The VRAM Trap
The limitation is not compute contexts, but **VRAM capacity**. 
If you set `replicas: 10` on a 16GB GPU, each pod mathematically has an absolute maximum of 1.6GB of VRAM available, excluding driver overhead. 

If you use high replica counts, PyTorch memory fractioning (`set_per_process_memory_fraction`) becomes strictly critical to prevent out-of-memory (OOM) errors.
```python
# For replicas: 10 on a 16GB GPU, limit each process to ~1.4GB
torch.cuda.set_per_process_memory_fraction(0.08, device=0) 
```

---

## 2. Multi-GPU Servers (Asymmetric Slicing)

On a server with multiple GPUs (e.g., 4x RTX 5090s, each with 32GB VRAM), you usually do not want to slice all GPUs equally. 

**Example Desired Topology:**
- **GPU 0:** Sliced into 7 parts (for lightweight Embedding APIs).
- **GPU 1:** Sliced into 2 parts (for heavy Vision/LLM Inference).
- **GPU 2 & 3:** Left unsliced (1:1 passthrough for heavy distributed PyTorch training).

### Configuring Asymmetric Slicing

To achieve this, we use **NVIDIA Device Plugin Profiles** and **Kubernetes Node Labels**.

1. Create a `ConfigMap` with multiple slicing profiles:
```yaml
# manifests/gpu/advanced-slicing-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin-config
  namespace: kube-system
data:
  config.yaml: |
    version: v1
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 7
          # Apply only to GPUs with specific UUID or index if supported, 
          # but practically, you apply configs at the NODE level.
```
*Note: The standard NVIDIA Device Plugin applies the Time-Slicing config uniformly to all GPUs on a single node. To achieve per-GPU asymmetric slicing on a single physical host, you must run multiple instances of the device plugin (one per physical GPU, using the `NVIDIA_VISIBLE_DEVICES` env var to restrict scope), each pointing to a different ConfigMap.*

### Better Approach: Node-Level Asymmetry
The standard Kubernetes pattern is to achieve asymmetry at the **Node** level across a cluster:
- **Node A (Inference Node 1):** Sliced 7 ways (Node label: `gpu-slice: embeddings`)
- **Node B (Inference Node 2):** Sliced 2 ways (Node label: `gpu-slice: vision`)
- **Node C (Training Node):** Unsliced (Node label: `gpu-slice: none`)

You then use `nodeSelector` in your workloads:
```yaml
nodeSelector:
  gpu-slice: embeddings
```

---

## 3. Management UIs

Managing complex Time-Slicing topologies strictly through YAML and `kubectl` can become unwieldy. 

### Enterprise Solutions
Tools like **Run:ai** provide an enterprise-grade control plane that sits on top of Kubernetes, dynamically managing GPU fractional allocation, queuing, and preemption with a clean UI.

### Custom Dashboards
You can build a custom **React** or **Flutter** UI that interacts with the Kubernetes API (`/api/v1/namespaces/kube-system/configmaps/nvidia-device-plugin-config`) to dynamically update the replica counts on the fly. When the ConfigMap updates, the Device Plugin can be configured to dynamically reload, instantly altering the topological layout of the cluster.

### Observability with Grafana
For purely visual management without mutation, rely on the **DCGM Exporter**.
Build Grafana panels that group `DCGM_FI_DEV_FB_USED` by physical `gpu_id` and overlay the Time-Slice replica IDs to visually confirm that your fractional VRAM limits are holding steady across the arbitrary slices.
