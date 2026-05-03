# GPU Time-Slicing Configuration

**Component:** NVIDIA Device Plugin with Time-Slicing  
**Objective:** Split 1 physical RTX 5070 Ti (16GB) into 4 logical GPU replicas  
**Namespace:** gpu-infrastructure  

---

## Prerequisites

Ensure infrastructure setup is complete from `01-infrastructure-setup.md`:

```bash
# Verify k3s is running
kubectl get nodes

# Verify Helm repositories are added
helm repo list

# Verify namespaces exist
kubectl get namespaces | grep gpu-infrastructure
```

---

## Step 1: Understand Time-Slicing Configuration

### Time-Slicing vs. MIG

Since the RTX 5070 Ti is a consumer GPU, it lacks hardware-level MIG (Multi-Instance GPU) support. Time-Slicing is the software-based alternative that:
- Divides GPU compute time into temporal slices (default: 10ms)
- Presents multiple logical GPU replicas to the Kubernetes scheduler
- Enables concurrent pod execution on a single physical GPU

### Configuration Parameters

| **Parameter** | **Value** | **Purpose** |
|---------------|-----------|-------------|
| `migStrategy` | `none` | Disable MIG (required for consumer GPUs) |
| `replicas` | `4` | Create 4 logical GPU replicas from 1 physical GPU |
| `renameByDefault` | `false` | Keep resource name as `nvidia.com/gpu` (not renamed) |
| `failRequestsGreaterThanOne` | `true` | Reject pod requests for >1 GPU (enforce 1:1 mapping) |
| `maxShares` | `4` | Upper bound on replication factor |

---

## Step 2: Deploy NVIDIA Device Plugin

### Install Device Plugin via Helm

```bash
# Install NVIDIA Device Plugin in gpu-infrastructure namespace
helm install nvidia-device-plugin nvidia/k8s-device-plugin \
  --namespace gpu-infrastructure \
  --version v0.15.0 \
  --set deviceListStrategy=volumeMount \
  --set migStrategy=none \
  --set gds.enabled=false \
  --set mofed.enabled=false
```

**Helm Values Explained:**
- `deviceListStrategy=volumeMount`: Mount GPU devices as volumes (required for Docker runtime)
- `migStrategy=none`: Explicitly disable MIG (consumer GPU)
- `gds.enabled=false`: Disable GPU Direct Storage (not supported on RTX 5070 Ti)
- `mofed.enabled=false`: Disable Mellanox OFED (not required for single-node)

### Verify Device Plugin Deployment

```bash
# Check Device Plugin DaemonSet status
kubectl get daemonset -n gpu-infrastructure

# Expected output:
# NAME                    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
# nvidia-device-plugin    1         1         1       1            1           <none>          10s

# Check Device Plugin pods
kubectl get pods -n gpu-infrastructure -l name=nvidia-device-plugin-ds

# Expected output:
# NAME                         READY   STATUS    RESTARTS   AGE
# nvidia-device-plugin-xxxxx   1/1     Running   0          15s
```

### Verify GPU Resource Advertisement (Before Time-Slicing)

```bash
# Check node allocatable resources
kubectl describe node gpu-node-1 | grep -A 15 "Allocatable"

# Expected output (before Time-Slicing):
# Allocatable:
#   cpu:                16
#   ephemeral-storage:  123456789Ki
#   memory:             32888888Ki
#   nvidia.com/gpu:     1
#   pods:               110
```

**Note:** At this stage, you should see `nvidia.com/gpu: 1` (single physical GPU). Time-Slicing will increase this to 4.

---

## Step 3: Create Time-Slicing ConfigMap

### ConfigMap YAML

Create the Time-Slicing configuration file:

```bash
# Create ConfigMap file
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
```

### Apply ConfigMap

```bash
# Apply the ConfigMap
kubectl apply -f time-slicing-configmap.yaml

# Verify ConfigMap creation
kubectl get configmap -n gpu-infrastructure nvidia-device-plugin-config

# Expected output:
# NAME                         DATA   AGE
# nvidia-device-plugin-config  1      5s
```

---

## Step 4: Restart Device Plugin to Load Config

The Device Plugin must be restarted to pick up the new Time-Slicing configuration.

```bash
# Delete the Device Plugin pod to trigger restart
kubectl delete pod -n gpu-infrastructure -l name=nvidia-device-plugin-ds

# Wait for the pod to restart (should be automatic)
kubectl get pods -n gpu-infrastructure -l name=nvidia-device-plugin-ds -w
```

**Expected Behavior:** The DaemonSet controller will automatically create a new pod with the Time-Slicing configuration loaded.

---

## Step 5: Verify Time-Slicing Configuration

### Check Device Plugin Logs

```bash
# View Device Plugin logs to confirm Time-Slicing is active
kubectl logs -n gpu-infrastructure -l name=nvidia-device-plugin-ds --tail=50

# Look for log entries indicating Time-Slicing configuration:
# "Starting NVML"
# "Sharing config loaded"
# "TimeSlicing: enabled for nvidia.com/gpu with replicas: 4"
```

### Verify GPU Replicas in Scheduler

```bash
# Check node allocatable resources again
kubectl describe node gpu-node-1 | grep -A 15 "Allocatable"

# Expected output (after Time-Slicing):
# Allocatable:
#   cpu:                16
#   ephemeral-storage:  123456789Ki
#   memory:             32888888Ki
#   nvidia.com/gpu:     4
#   pods:               110
```

**Critical Verification:** You should now see `nvidia.com/gpu: 4` instead of `nvidia.com/gpu: 1`. This confirms the scheduler sees 4 logical GPU replicas.

### Verify Capacity vs. Allocatable

```bash
# Check both Capacity and Allocatable to understand the split
kubectl describe node gpu-node-1 | grep -A 20 "Capacity"

# Expected output:
# Capacity:
#   cpu:                16
#   ephemeral-storage:  123456789Ki
#   hugepages-1Gi:      0
#   hugepages-2Mi:      0
#   memory:             32888888Ki
#   nvidia.com/gpu:     4
#   pods:               110
```

**Note:** Both Capacity and Allocatable show `nvidia.com/gpu: 4`. This is correct for Time-Slicing (unlike MIG, which would show Capacity: 1, Allocatable: 4).

---

## Step 6: Test GPU Allocation

### Create Test Pod

Create a simple test pod to verify GPU allocation works:

```bash
cat <<EOF > test-gpu-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test-pod
  namespace: gpu-infrastructure
spec:
  containers:
  - name: gpu-test
    image: nvidia/cuda:12.1.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
  restartPolicy: Never
EOF

# Apply the test pod
kubectl apply -f test-gpu-pod.yaml
```

### Verify Test Pod Execution

```bash
# Watch pod status
kubectl get pod gpu-test-pod -n gpu-infrastructure -w

# Expected sequence:
# NAME           READY   STATUS              RESTARTS   AGE
# gpu-test-pod   0/1     ContainerCreating   0          1s
# gpu-test-pod   0/1     Running             0          3s
# gpu-test-pod   0/1     Completed           0          5s

# View pod logs to confirm GPU access
kubectl logs gpu-test-pod -n gpu-infrastructure

# Expected output: nvidia-smi output showing RTX 5070 Ti
```

### Clean Up Test Pod

```bash
# Delete the test pod
kubectl delete pod gpu-test-pod -n gpu-infrastructure
```

---

## Step 7: Verify Multiple Concurrent Pods

### Create Three Concurrent Test Pods

```bash
# Create three pods to simulate our workload scenario
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

# Apply the pods
kubectl apply -f multi-gpu-test.yaml
```

### Verify All Pods Run Concurrently

```bash
# Check pod status
kubectl get pods -n gpu-infrastructure

# Expected output:
# NAME         READY   STATUS    RESTARTS   AGE
# gpu-test-1   1/1     Running   0          10s
# gpu-test-2   1/1     Running   0          10s
# gpu-test-3   1/1     Running   0          10s
```

**Critical Verification:** All three pods should be in `Running` state simultaneously. This confirms Time-Slicing is working correctly.

### Check GPU Usage from Within Pods

```bash
# Execute nvidia-smi inside each pod
kubectl exec -n gpu-infrastructure gpu-test-1 -- nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader
kubectl exec -n gpu-infrastructure gpu-test-2 -- nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader
kubectl exec -n gpu-infrastructure gpu-test-3 -- nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader

# All pods should report the same physical GPU (GPU 0)
```

### Clean Up Test Pods

```bash
# Delete all test pods
kubectl delete -f multi-gpu-test.yaml
```

---

## Step 8: Verify Device Plugin Configuration Persistence

### Check ConfigMap Persistence

```bash
# Verify ConfigMap still exists
kubectl get configmap -n gpu-infrastructure nvidia-device-plugin-config -o yaml

# Expected output should show the time-slicing configuration
```

### Check Device Plugin Configuration

```bash
# Get the Device Plugin DaemonSet configuration
kubectl get daemonset -n gpu-infrastructure nvidia-device-plugin -o yaml

# Verify it references the ConfigMap:
# spec:
#   template:
#     spec:
#       containers:
#       - name: nvidia-device-plugin
#         env:
#         - name: NVIDIA_DEVICE_PLUGIN_CONFIG
#           value: /etc/nvidia-device-plugin/config.yaml
#         volumeMounts:
#         - name: config-volume
#           mountPath: /etc/nvidia-device-plugin
#       volumes:
#       - name: config-volume
#         configMap:
#           name: nvidia-device-plugin-config
```

---

## Verification Checklist

### ✅ Device Plugin Verification

```bash
# 1. Device Plugin DaemonSet is running
kubectl get daemonset -n gpu-infrastructure nvidia-device-plugin
# Expected: DESIRED=1, CURRENT=1, READY=1

# 2. Device Plugin pod is running
kubectl get pods -n gpu-infrastructure -l name=nvidia-device-plugin-ds
# Expected: 1/1 Running

# 3. Device Plugin logs show Time-Slicing enabled
kubectl logs -n gpu-infrastructure -l name=nvidia-device-plugin-ds | grep -i "timeslicing"
# Expected: Log entries indicating Time-Slicing configuration
```

### ✅ Scheduler Verification

```bash
# 4. Node shows 4 GPU replicas
kubectl describe node gpu-node-1 | grep "nvidia.com/gpu"
# Expected: nvidia.com/gpu: 4 (in both Capacity and Allocatable)

# 5. ConfigMap exists with correct configuration
kubectl get configmap -n gpu-infrastructure nvidia-device-plugin-config -o yaml
# Expected: config.yaml with replicas: 4
```

### ✅ Functional Verification

```bash
# 6. Single pod can request GPU
kubectl apply -f test-gpu-pod.yaml
kubectl wait --for=condition=completed -n gpu-infrastructure pod/gpu-test-pod --timeout=60s
# Expected: Pod completes successfully

# 7. Multiple pods can run concurrently
kubectl apply -f multi-gpu-test.yaml
kubectl wait --for=condition=ready -n gpu-infrastructure pod/gpu-test-1 --timeout=60s
kubectl wait --for=condition=ready -n gpu-infrastructure pod/gpu-test-2 --timeout=60s
kubectl wait --for=condition=ready -n gpu-infrastructure pod/gpu-test-3 --timeout=60s
# Expected: All pods reach Ready state
```

---

## Troubleshooting

### Issue: Scheduler still shows nvidia.com/gpu: 1

**Symptom:** `kubectl describe node` shows `nvidia.com/gpu: 1` after applying ConfigMap.

**Solution:**
```bash
# Verify ConfigMap was applied
kubectl get configmap -n gpu-infrastructure nvidia-device-plugin-config

# Restart Device Plugin pod
kubectl delete pod -n gpu-infrastructure -l name=nvidia-device-plugin-ds

# Wait for pod restart and check again
kubectl get pods -n gpu-infrastructure -l name=nvidia-device-plugin-ds -w
kubectl describe node gpu-node-1 | grep "nvidia.com/gpu"
```

### Issue: Pods stuck in ContainerCreating state

**Symptom:** Pods requesting GPU never start, staying in ContainerCreating.

**Solution:**
```bash
# Check pod events
kubectl describe pod <pod-name> -n gpu-infrastructure

# Common error: "Insufficient nvidia.com/gpu"
# This means Time-Slicing is not working correctly

# Check Device Plugin logs
kubectl logs -n gpu-infrastructure -l name=nvidia-device-plugin-ds

# Verify ConfigMap configuration
kubectl get configmap -n gpu-infrastructure nvidia-device-plugin-config -o yaml
```

### Issue: Device Plugin pod crashes repeatedly

**Symptom:** Device Plugin pod has CrashLoopBackOff status.

**Solution:**
```bash
# Check pod logs
kubectl logs -n gpu-infrastructure -l name=nvidia-device-plugin-ds --previous

# Common causes:
# 1. NVIDIA driver not loaded (verify with nvidia-smi)
# 2. Docker runtime not configured (verify with docker info)
# 3. ConfigMap syntax error (verify YAML syntax)

# If driver issue:
nvidia-smi
sudo systemctl restart docker
kubectl delete pod -n gpu-infrastructure -l name=nvidia-device-plugin-ds
```

### Issue: Pods cannot access GPU despite allocation

**Symptom:** Pod runs but `nvidia-smi` inside pod fails.

**Solution:**
```bash
# Verify Docker runtime configuration
sudo docker info | grep -i "runtime"

# Reconfigure NVIDIA runtime if needed
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Restart Device Plugin
kubectl delete pod -n gpu-infrastructure -l name=nvidia-device-plugin-ds
```

---

## Advanced Configuration

### Adjusting Time-Slice Duration

The default time slice is 10ms. To adjust for different latency requirements:

```bash
# Edit the ConfigMap to add timeSliceDuration
kubectl edit configmap nvidia-device-plugin-config -n gpu-infrastructure

# Add to config.yaml:
# timeSlicing:
#   renameByDefault: false
#   failRequestsGreaterThanOne: true
#   maxShares: 4
#   timeSliceDuration: 5000000  # 5ms in nanoseconds

# Restart Device Plugin
kubectl delete pod -n gpu-infrastructure -l name=nvidia-device-plugin-ds
```

**Note:** Lower time slices reduce latency but increase context switching overhead. 10ms is optimal for most inference workloads.

### Changing Replica Count

To adjust the number of logical GPU replicas:

```bash
# Edit ConfigMap
kubectl edit configmap nvidia-device-plugin-config -n gpu-infrastructure

# Change replicas value:
# resources:
#   - name: nvidia.com/gpu
#     replicas: 2  # Reduce from 4 to 2

# Restart Device Plugin
kubectl delete pod -n gpu-infrastructure -l name=nvidia-device-plugin-ds

# Verify new replica count
kubectl describe node gpu-node-1 | grep "nvidia.com/gpu"
```

**Caution:** Reducing replicas may require deleting existing GPU-allocated pods before the scheduler recognizes the change.

---

## Next Steps

With GPU Time-Slicing configured and verified, proceed to:

**Document 3:** `03-workloads-and-memory.md`

This document covers:
- Deploying FastAPI and PyTorch services with GPU requests
- Configuring Kubernetes resource limits to prevent OOM
- Implementing PyTorch memory fractioning for VRAM isolation
