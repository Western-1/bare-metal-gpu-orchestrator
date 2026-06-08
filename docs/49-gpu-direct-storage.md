# GPU Direct Storage (GDS)

**Component:** Hardware I/O Optimization  
**Objective:** Maximize data transfer rates by bypassing CPU architecture  
**Architecture:** Magnum IO / NVIDIA GDS  

---

## 1. The Standard I/O Bottleneck

In a traditional ML loading sequence (e.g., loading a 40GB LLM into VRAM):
1. The NVMe drive reads the bytes into the Linux page cache (CPU RAM).
2. The CPU processes the data (Bounce Buffer).
3. The CPU copies the data across the PCIe bus into the GPU VRAM.

This 3-step process consumes massive CPU cycles, saturates system memory bandwidth, and creates a severe bottleneck. During scale-out events (e.g., KEDA spinning up 3 new Pods), this initialization delay prevents the application from responding to sudden traffic spikes.

---

## 2. NVIDIA GPUDirect Storage Architecture

**GPUDirect Storage (GDS)** establishes a direct Direct Memory Access (DMA) path between the local NVMe storage arrays (configured in `25-storage-io-optimization.md`) and the GPU VRAM.

1. The data traverses directly from the NVMe PCIe lanes to the GPU PCIe lanes.
2. The CPU is completely bypassed.
3. System RAM is not utilized.

**Result:** I/O throughput increases from ~3 GB/s to >10 GB/s, drastically reducing cold-start times for massive foundation models.

---

## 3. Configuration and Deployment

### 3.1 Kernel and Driver Prerequisites

GDS requires specific kernel modules (`nvidia-fs`) integrated with the standard NVIDIA driver installation.

```bash
# Install GDS kernel modules on Ubuntu
sudo apt-get install nvidia-gds

# Verify the direct memory path
/usr/local/cuda/gds/tools/gdscheck -p
```

### 3.2 Application Integration (PyTorch)

GDS is not entirely transparent; the application must utilize the `cuFile` API. Fortunately, modern frameworks support this natively.

To force PyTorch to utilize GDS for tensor loading, ensure the environment variables are injected into the Deployment manifests.

```yaml
# Pod Spec Excerpt
        env:
        # Enable the cuFile API for GPUDirect Storage
        - name: CUFILE_ENV_PATH_JSON
          value: "/etc/cufile.json"
        # Force PyTorch DataLoader and serialization to use GDS
        - name: PYTORCH_NO_CUDA_MEMORY_CACHING
          value: "1"
```

### 3.3 Validating the DMA Path

During a model load, utilize the `nvidia-smi` specific GDS flags or `iostat` to verify that CPU utilization remains near 0% while NVMe read speeds and GPU PCIe write speeds hit physical maximums.

---

## Next Steps

Proceed to `50-continuous-ml-cml.md` to automate the reporting of these model training runs into Git Pull Requests.
