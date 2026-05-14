# Advanced Multi-GPU Topologies

**Component:** NVIDIA Device Plugin & Node Labels  
**Objective:** Scale fractional compute across multi-GPU nodes (e.g., 4x RTX 5090)  
**Strategy:** Asymmetric Time-Slicing  

---

## 1. Arbitrary Time-Slicing Configuration

The baseline architecture utilizes `replicas: 4` for the GPU Time-Slicing ConfigMap. This is a software-defined multiplexing parameter, not a hardware constraint. The replica count can mathematically scale arbitrarily (e.g., 10, 20).

### The VRAM Constraint

The limiting factor in Time-Slicing is absolute VRAM capacity, not compute contexts. 
Deploying `replicas: 10` on a 16GB GPU restricts each logical slice to ~1.4GB of VRAM (accounting for CUDA context overhead). 

Strict enforcement of PyTorch memory fractions is mandatory to prevent node-level OOM cascading:

```python
# Implementation for 10 replicas on a 16GB GPU (1.4GB per process)
torch.cuda.set_per_process_memory_fraction(0.08, device=0) 
```

---

## 2. Asymmetric Slicing on Multi-GPU Servers

Multi-GPU architectures demand heterogeneous slicing strategies. Uniform slicing across all physical GPUs on a heavy compute node is an anti-pattern.

**Target Topology (4x GPU Node):**
- **GPU 0:** 7 slices (High-throughput Embedding API)
- **GPU 1:** 2 slices (Heavy Vision/LLM Inference)
- **GPU 2 & 3:** 0 slices / 1:1 Passthrough (Distributed PyTorch Training)

### Implementation Strategy

The default NVIDIA Device Plugin applies a single ConfigMap globally across all detected GPUs on the host. To achieve intra-node asymmetry, you must isolate the device plugin execution:

1. Disable the global DaemonSet device plugin for the target node.
2. Deploy independent device plugin instances targeted to specific physical GPUs via the `NVIDIA_VISIBLE_DEVICES` environment variable.
3. Map each isolated plugin to a unique ConfigMap containing the targeted replica count.

### Alternative: Node-Level Topology (Recommended)

Enterprise Kubernetes architectures abstract heterogeneity to the node level via `NodeLabels` and `NodeSelectors`, rather than complex intra-node isolation.

**Topology Definition:**
- **Node A (Inference 1):** Sliced 7x (`NodeLabel: gpu-profile=high-density`)
- **Node B (Inference 2):** Sliced 2x (`NodeLabel: gpu-profile=low-density`)
- **Node C (Training):** Unsliced (`NodeLabel: gpu-profile=passthrough`)

**Workload Assignment:**
```yaml
# Pod Spec Definition
nodeSelector:
  gpu-profile: high-density
```

---

## 3. Dynamic Topology Management

Static YAML management of dynamic GPU topographies scales poorly in production environments.

### Enterprise Orchestration
Commercial control planes (e.g., Run:ai) provide dynamic fractional allocation, workload queuing, and preemption layered above the native Kubernetes scheduler.

### API-Driven Reconfiguration
Topology mutations can be automated via the Kubernetes API. Updating the target `ConfigMap` (`/api/v1/namespaces/kube-system/configmaps/nvidia-device-plugin-config`) and triggering a plugin reload instantly modifies the cluster's logical GPU pool without host reboots.

### Telemetry and Validation
Validate arbitrary slicing boundaries via DCGM Exporter telemetry.
Map `DCGM_FI_DEV_FB_USED` against physical `gpu_id` to verify that fractional VRAM caps are successfully preventing memory boundary violations within the defined slices.

---

## Next Steps

Proceed to `15-dynamic-batching-vllm.md` to configure continuous batching and PagedAttention for LLM workloads.
