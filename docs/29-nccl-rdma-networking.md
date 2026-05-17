# RDMA and NCCL Networking

**Component:** High-Performance Networking  
**Objective:** Maximize bandwidth and minimize latency for Multi-Node Tensor Operations  
**Architecture:** RoCEv2 (RDMA over Converged Ethernet) & NVIDIA NCCL  

---

## 1. TCP/IP Bottleneck in Distributed ML

In a distributed Ray cluster (`21-ray-distributed-ml.md`), training massive models demands constant synchronization of gradients across network boundaries.
Standard Ethernet relying on the host OS TCP/IP stack introduces unacceptable overhead:
- **High CPU Utilization:** Packet processing consumes CPU cycles.
- **Latency Spikes:** Kernel space context switching delays tensor delivery.
- **Bandwidth Saturation:** TCP headers and retransmissions bottleneck 100Gbps+ interfaces.

---

## 2. RDMA and RoCEv2 Architecture

**Remote Direct Memory Access (RDMA)** allows one machine to write data directly into the VRAM of a GPU on a remote machine, completely bypassing the host OS kernel and CPU.

**RoCEv2** encapsulates RDMA frames within standard UDP/IP packets, allowing deployment over standard Converged Ethernet switches (provided they support Priority Flow Control).

### NVIDIA NCCL Integration

The NVIDIA Collective Communications Library (NCCL) is the de-facto standard for multi-GPU topology detection and tensor synchronization. When configured correctly, PyTorch delegates `AllReduce` and `AllGather` operations to NCCL, which native exploits RDMA hardware via the InfiniBand Verbs API.

---

## 3. Bare-Metal Network Configuration

To enable RoCEv2, the underlying hardware (e.g., Mellanox ConnectX NICs) and OS must be configured for RDMA operations.

### OS Dependencies

```bash
# Install RDMA core user-space libraries
sudo apt-get install rdmacm-utils ibverbs-utils perftest -y

# Verify RDMA interfaces
ibv_devinfo
```

---

## 4. Kubernetes and Workload Configuration

For a Kubernetes pod to utilize RoCEv2, it must gain access to the host's Infiniband character devices.

### SRIOV Network Device Plugin

Deploy the SR-IOV or Mellanox Network Operator to advertise RDMA virtual functions to the Kubernetes scheduler, similar to the NVIDIA Device Plugin.

### Pod Execution Environment Variables

To force KubeRay and PyTorch to utilize NCCL over RDMA (disabling TCP fallback), inject the following environment variables into the Ray Worker deployment specifications:

```yaml
# KubeRay RayCluster Spec Excerpt
          env:
            - name: NCCL_DEBUG
              value: "INFO"             # Enable telemetry for topology verification
            - name: NCCL_IB_DISABLE
              value: "0"                # Explicitly enable InfiniBand/RoCE
            - name: NCCL_IB_GID_INDEX
              value: "3"                # Typically 3 for RoCEv2 (validate via show_gids)
            - name: NCCL_NET_GDR_LEVEL
              value: "2"                # Enable GPUDirect RDMA
```

---

## 5. Verification Protocol

Validate the topology during a distributed PyTorch training run. Inspect the worker pod stdout for the NCCL initialization block.

**Expected Log Output:**
```text
[Node 0] NCCL INFO NET/IB : Using [0]mlx5_0:1/RoCE ; OOB eth0:10.0.0.51
[Node 0] NCCL INFO Using network IB
```
*If NCCL outputs `NET/Socket`, the RDMA topology has failed and fallback to standard TCP is active.*

---

## Next Steps

Proceed to `30-continuous-profiling-pyroscope.md` to analyze CPU bottlenecks within the inference pipelines.
