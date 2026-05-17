# Architecture: MIG vs. Time-Slicing

**Component:** Hardware Multiplexing Topologies  
**Objective:** Define constraints and selection criteria for GPU partitioning strategies  

---

## 1. Introduction to GPU Multiplexing

Modern Machine Learning topologies require maximum GPU utilization. Deploying a single low-traffic microservice (e.g., an Embedding API generating vectors at 10 requests/sec) onto a dedicated 16GB/24GB GPU results in ~5% hardware utilization, leading to catastrophic ROI failure.

To optimize CapEx, the orchestrator must pack multiple workloads onto the physical silicon. NVIDIA provides two distinct mechanisms for this: **Multi-Instance GPU (MIG)** and **Time-Slicing**.

---

## 2. Multi-Instance GPU (MIG)

MIG is a hardware-level partitioning technology available strictly on NVIDIA Enterprise Architecture (e.g., Ampere A100, Hopper H100).

### Mechanics
MIG physically partitions the GPU's Compute Units (SMs) and Memory Controllers. A single 80GB H100 can be severed into 7 fully isolated instances (e.g., 7x 10GB partitions).

### Advantages
- **Fault Isolation:** If a workload in MIG Partition 1 encounters an infinite loop or SegFault, it physically cannot impact MIG Partition 2.
- **Memory Bandwidth Guarantee:** Each partition has dedicated lanes to the L2 Cache and HBM memory.
- **Deterministic Latency:** Zero context-switching overhead.

### Disadvantages
- **Cost:** Requires Enterprise GPUs ($10,000 - $35,000+ per card).
- **Rigidity:** Reconfiguring MIG instances requires draining workloads and resetting the hardware topology.

---

## 3. GPU Time-Slicing

Time-Slicing is a software-level multiplexing topology available on virtually all modern NVIDIA GPUs, including Consumer/Prosumer cards (e.g., RTX 4090, RTX 5070 Ti, RTX 6000 Ada). This is the topology utilized in this repository.

### Mechanics
Time-Slicing operates similarly to a CPU scheduler. The NVIDIA driver rapidly context-switches active Compute streams across the entire unified hardware die. Memory is partitioned purely by software limits, not hardware barriers.

### Advantages
- **Cost-Efficiency:** Unlocks enterprise-grade orchestration density on consumer bare-metal hardware.
- **Dynamic Capacity:** A workload can burst to utilize 100% of the SM (Compute) cores if neighboring slices are idle.
- **Flexibility:** Altering the replica count in the ConfigMap requires only a DaemonSet reload, not a physical hardware reset.

### Disadvantages
- **Memory Violation Risk:** Software VRAM limits are easily violated. If Pod A exceeds its fraction, it triggers a global OOM state affecting all Time-Sliced Pods on the die (mitigated via strict `asyncio.Semaphore` implementations).
- **Context-Switching Latency:** Minor overhead due to the scheduler swapping CUDA contexts.

---

## 4. Selection Matrix

| **Metric** | **Hardware MIG** | **Software Time-Slicing** |
|------------|------------------|---------------------------|
| **Supported Hardware** | Enterprise (A100, H100, H200) | Consumer/Prosumer (RTX 4090, RTX 5070 Ti) |
| **Compute Isolation** | High (Physical SM segregation) | Low (Time-division multiplexing) |
| **Memory Isolation** | Perfect (Hardware barriers) | Poor (Software limits only) |
| **Burst Capability** | None (Locked to partition limits) | High (Can consume idle neighboring compute) |
| **Primary Use Case** | Multi-tenant untrusted code execution | Trusted microservices, bursty inference |

**Conclusion:** For internal organizational deployments where workloads are trusted and VRAM limits can be strictly governed via code (`set_per_process_memory_fraction`), Time-Slicing on Consumer hardware provides a drastically superior Price/Performance ratio compared to Enterprise MIG provisioning.

---

## Next Steps

Proceed to `32-spot-instance-preemption.md` to configure workload survivability during sudden node termination events.
