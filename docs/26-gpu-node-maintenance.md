# GPU Node Maintenance and Updates

**Component:** Kubernetes Node Administration  
**Objective:** Execute Kernel/Driver patches with Zero-Downtime  
**Protocol:** Kubernetes Cordon and Drain  

---

## 1. Maintenance Imperative

Bare-metal infrastructure requires routine patching:
- NVIDIA Driver/CUDA updates for vulnerability mitigation or performance enhancements.
- Host OS kernel patches.
- Physical hardware remediation.

Abruptly executing `sudo reboot` severs active client connections and orphans in-flight CUDA tensors. A strict cordon-and-drain protocol is mandatory to orchestrate graceful workload migration.

---

## 2. Zero-Downtime Drain Protocol

This runbook assumes a multi-node architecture (or graceful queue buffering via KEDA/Redis for single-node setups).

### Step 1: Cordon the Node
Mark the node as unschedulable. Kubernetes will reject any newly scheduled pods from landing on this host.

```bash
kubectl cordon <node-name>

# Verification
kubectl get nodes
# Expected output status: Ready,SchedulingDisabled
```

### Step 2: Drain the Workloads
Evict all existing workloads safely. The `--ignore-daemonsets` flag is required to bypass system components like the NVIDIA Device Plugin.

```bash
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force \
  --grace-period=120
```

*Note: The `--grace-period=120` instructs Kubernetes to send `SIGTERM` to the ML APIs, allowing them 120 seconds to finalize in-flight synchronous inferences before executing a `SIGKILL`.*

---

## 3. Execution of System Patches

With all workloads safely rescheduled to auxiliary nodes (or paused in Redis), execute host-level mutations.

### Update NVIDIA Drivers

```bash
# Halt device plugin and Kubelet locally
sudo systemctl stop k3s

# Apply driver updates
sudo apt-get update
sudo apt-get install --only-upgrade nvidia-driver-535 nvidia-utils-535

# Execute reboot to apply kernel modules
sudo reboot
```

---

## 4. Reintegration Protocol

Upon server initialization, validate hardware telemetry before enabling Kubernetes scheduling.

### Step 1: Hardware Validation
Ensure the NVIDIA kernel module is loaded and operational.

```bash
nvidia-smi
# Verify Driver Version and CUDA compilation target
```

### Step 2: Uncordon the Node
Restore the node's scheduling pool status.

```bash
kubectl uncordon <node-name>

# Verification
kubectl get nodes
# Expected output status: Ready
```

### Step 3: Workload Rebalancing (Optional)
Kubernetes does not proactively rebalance pods from saturated nodes onto newly uncordoned nodes. To trigger rebalancing, you can implement the `descheduler` controller, or manually cycle target deployments:

```bash
kubectl rollout restart deployment/embedding-service -n ml-workloads
```

---

## 5. Edge Case: Single-Node Clusters

If operating a single-node cluster, `kubectl drain` will hang as there are no auxiliary nodes to absorb the workloads. 

**Single-Node Update Flow:**
1. Manually scale all synchronous APIs down to 0:
   `kubectl scale deployment embedding-service --replicas=0 -n ml-workloads`
2. Allow asynchronous workers to drain their respective Redis queues.
3. Stop k3s, execute maintenance, and reboot.
4. Scale deployments back to target replica counts.
