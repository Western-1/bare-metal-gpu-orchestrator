# Node Resource Reservation

**Component:** Kubelet / k3s  
**Objective:** Prevent OS-level OOM and `DiskPressure` state during heavy ML execution  
**Target:** System Stability  

---

## 1. The Resource Exhaustion Problem

By default, Kubernetes (and k3s) schedules pods assuming they can utilize all available CPU and Memory on the node.
In an MLOps environment:
- Loading multiple 10GB models into VRAM requires equivalent temporary system RAM.
- PyTorch DataLoader workers (if configured improperly) can spike CPU utilization to 100%.
- If system RAM is exhausted, the Linux Out-Of-Memory (OOM) killer may target the `kubelet` or `containerd` processes, causing the node to transition to a `NotReady` state and catastrophic failure of all workloads.

## 2. Solution: Kubelet Reservations

To protect the host operating system and Kubernetes control plane, we enforce hard reservations. The `kubelet` subtracts these reservations from the node's total capacity, ensuring workloads cannot schedule if they would encroach on system limits.

### Configuration Topology

- **kube-reserved:** Resources allocated for Kubernetes system daemons (`kubelet`, `containerd`, CNI).
- **system-reserved:** Resources allocated for OS system daemons (`sshd`, `systemd`, `udev`).
- **eviction-hard:** Thresholds at which the node aggressively evicts lower-priority pods to survive.

---

## 3. Implementation in k3s

To configure reservations in k3s on a bare-metal node, modify the startup configuration.

### Apply Configuration

```bash
# Append Kubelet arguments to the k3s configuration file
cat <<EOF | sudo tee -a /etc/rancher/k3s/config.yaml

# Kubelet Resource Reservation
kubelet-arg:
  - "kube-reserved=cpu=1,memory=2Gi,ephemeral-storage=2Gi"
  - "system-reserved=cpu=1,memory=2Gi,ephemeral-storage=2Gi"
  - "eviction-hard=memory.available<1Gi,nodefs.available<5Gi,imagefs.available<5Gi"
  - "enforce-node-allocatable=pods,system-reserved,kube-reserved"
EOF

# Restart the k3s service to apply
sudo systemctl restart k3s
```

### Resource Math Example (Server with 32GB RAM & 16 CPU)

- **Total Capacity:** 32GB RAM, 16 CPU
- **Reserved:** 4GB RAM (2Gi kube + 2Gi system), 2 CPU
- **Allocatable Capacity:** 28GB RAM, 14 CPU

Pod schedulers will now strictly operate within the 28GB RAM limit.

---

## 4. Verification

Validate the reservation via the Kubernetes API:

```bash
kubectl describe node <node-name> | grep -A 7 "Allocatable:"

# Expected Output:
# Capacity:
#   cpu:                16
#   memory:             32Gi
# Allocatable:
#   cpu:                14
#   memory:             28Gi
```

---

## Next Steps

Proceed to `23-model-quantization-strategies.md` to optimize memory footprints via quantization.
