# Storage I/O Optimization and RAID

**Component:** Local Storage (NVMe/SSD)  
**Objective:** Maximize Disk Read Throughput (IOPS) for Cold Starts  
**Architecture:** mdadm RAID 0 & XFS  

---

## 1. The I/O Bottleneck in MLOps

While GPUs handle computation, raw storage I/O dictates initialization latency. 
When a pod crashes or dynamically scales, it must load multi-gigabyte tensor files (`.safetensors`, `.bin`) from disk into system RAM, and subsequently into VRAM.

A standard SATA SSD caps out at ~500 MB/s. Loading a 15GB model takes roughly 30 seconds. On highly scaled nodes loading multiple models concurrently, disk I/O saturation triggers severe latency spikes.

---

## 2. Hardware RAID 0 Topology

To circumvent I/O constraints, utilize multiple NVMe drives striped into a RAID 0 array. 
*Note: RAID 0 provides zero redundancy. It is strictly deployed as an ephemeral cache layer (`HostPath` PVCs for models) where data loss implies only a re-download from HuggingFace.*

### 2.1 Array Initialization

Identify available unmounted NVMe drives (e.g., `/dev/nvme1n1`, `/dev/nvme2n1`):

```bash
# Verify block devices
lsblk

# Create RAID 0 array
sudo mdadm --create --verbose /dev/md0 --level=0 --raid-devices=2 /dev/nvme1n1 /dev/nvme2n1

# Save RAID configuration to persist across reboots
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u
```

### 2.2 XFS Filesystem Formatting

XFS natively scales to high thread counts and is heavily optimized for large file I/O operations (ideal for monolithic model weights).

```bash
# Format the array with XFS
sudo mkfs.xfs /dev/md0

# Create mount point
sudo mkdir -p /mnt/ml-cache

# Add to fstab for automatic mounting
echo '/dev/md0 /mnt/ml-cache xfs defaults,noatime,discard 0 0' | sudo tee -a /etc/fstab

# Mount the array
sudo mount -a
```
*Note: `noatime` eliminates file access timestamp updates, reducing write amplification.*

---

## 3. Validation and Benchmarking

Verify sequential read capabilities using `fio`.

```bash
sudo apt-get install fio -y

# Execute sequential read benchmark
fio --name=read_benchmark \
    --directory=/mnt/ml-cache \
    --size=10G \
    --rw=read \
    --bs=1M \
    --direct=1 \
    --numjobs=4 \
    --ioengine=libaio \
    --iodepth=16
```
**Expected Result:** NVMe RAID 0 should yield sequential read speeds > 6000 MB/s, slashing a 15GB model load time to under 3 seconds.

---

## 4. Workload Integration

Update the Persistent Volume (from `12-model-caching-pvc.md`) to target the optimized array.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: hf-cache-pv
spec:
  storageClassName: local-path
  hostPath:
    path: "/mnt/ml-cache" # Target the RAID 0 array
```

---

## Next Steps

Proceed to `26-gpu-node-maintenance.md` for cluster operation runbooks and zero-downtime upgrades.
