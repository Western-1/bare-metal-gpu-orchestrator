# Infrastructure Setup: Bare-Metal Node Preparation

**Target OS:** Ubuntu 24.04 LTS  
**Hardware:** AMD Ryzen 7 7800X3D, NVIDIA RTX 5070 Ti (16GB), 32GB RAM  
**Purpose:** Prepare the bare-metal node for k3s, Docker, and GPU passthrough  

---

## Prerequisites

### System Requirements Verification

Before proceeding, verify your hardware meets the minimum specifications:

```bash
# Check CPU cores and threads
lscpu | grep "^CPU(s):"

# Check total system RAM
free -h | grep "Mem:"

# Check GPU presence and VRAM
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
```

**Expected Output:**
```
CPU(s):              16
Mem:                32Gi
NVIDIA RTX 5070 Ti, 16384 MiB
```

### System Update

Ensure your Ubuntu 24.04 system is fully updated:

```bash
# Update package lists and upgrade installed packages
sudo apt update && sudo apt upgrade -y

# Install essential build tools
sudo apt install -y curl wget git ca-certificates gnupg lsb-release
```

---

## Step 1: Install NVIDIA Drivers

### Remove Existing NVIDIA Packages

If you have existing NVIDIA packages, remove them to avoid conflicts:

```bash
sudo apt purge -y nvidia* libcuda* libnvidia*
sudo apt autoremove -y
```

### Install NVIDIA Driver 535+

Add the NVIDIA repository and install the recommended driver:

```bash
# Add NVIDIA repository
sudo add-apt-repository ppa:graphics-drivers/ppa -y
sudo apt update

# Install NVIDIA driver (535 is the minimum for CUDA 12.x support)
sudo apt install -y nvidia-driver-535

# Reboot to load the driver
sudo reboot
```

### Verify Driver Installation

After reboot, verify the driver is loaded correctly:

```bash
# Check driver version
nvidia-smi

# Verify CUDA version compatibility
nvidia-smi | grep "CUDA Version"
```

**Expected Output:**
```
Tue Jul  2 18:00:00 2026       
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 535.154.05   Driver Version: 535.154.05   CUDA Version: 12.2     |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|===============================+======================+======================|
|   0  NVIDIA RTX 5070 Ti  Off  | 00000000:01:00.0  On |                  N/A |
| 30%   42C    P8    12W / 300W |      4MiB / 16384MiB |      0%      Default |
+-------------------------------+----------------------+----------------------+
```

---

## Step 2: Install Docker Engine

### Remove Old Docker Versions

```bash
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y $pkg;
done
```

### Set Up Docker Repository

```bash
# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Set up the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os_release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
```

### Install Docker Engine

```bash
# Install Docker Engine, CLI, and Compose plugin
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Verify Docker installation
docker --version
```

**Expected Output:**
```
Docker version 27.0.0, build 0000000
```

### Add User to Docker Group

```bash
# Add current user to docker group
sudo usermod -aG docker $USER

# Apply group membership (log out and back in, or use newgrp)
newgrp docker
```

### Verify Docker Without Sudo

```bash
docker run hello-world
```

**Expected Output:**
```
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

---

## Step 3: Install NVIDIA Container Toolkit

### Add NVIDIA Repository

```bash
# Add NVIDIA Container Toolkit repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
```

### Install NVIDIA Container Toolkit

```bash
# Install the toolkit
sudo apt-get install -y nvidia-container-toolkit

# Verify installation
nvidia-container-cli --version
```

**Expected Output:**
```
NVIDIA Container Toolkit version: 1.16.0
```

### Configure Docker to Use NVIDIA Runtime

```bash
# Generate Docker daemon configuration with NVIDIA runtime
sudo nvidia-ctk runtime configure --runtime=docker

# Restart Docker daemon to apply configuration
sudo systemctl restart docker
```

### Verify Docker Configuration

```bash
# Check that nvidia runtime is configured
sudo docker info | grep -i "runtime"

# Expected output should include: nvidia
```

### Test GPU Passthrough with Docker

```bash
# Run a container with GPU access
docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi
```

**Expected Output:** Same as host `nvidia-smi` output, confirming GPU passthrough works.

---

## Step 4: Install k3s with Docker Runtime

### Install k3s with Docker Flag

```bash
# Download and install k3s with Docker runtime
curl -sfL https://get.k3s.io | sh -s - \
  --docker \
  --disable traefik \
  --disable servicelb \
  --node-name gpu-node-1 \
  --write-kubeconfig-mode 644 \
  --tls-san gpu-node-1
```

**Installation Flags Explained:**
- `--docker`: Use Docker as container runtime instead of containerd (required for NVIDIA Container Toolkit integration)
- `--disable traefik`: Disable default Traefik ingress (we'll use Nginx ingress later)
- `--disable servicelb`: Disable default ServiceLB (we'll use Nginx ingress for load balancing)
- `--node-name gpu-node-1`: Explicit node naming for consistent identification
- `--write-kubeconfig-mode 644`: Allow non-root users to read kubeconfig
- `--tls-san gpu-node-1`: Add node name to TLS certificate SANs for API access

### Verify k3s Installation

```bash
# Check k3s service status
sudo systemctl status k3s

# Verify k3s version
k3s --version
```

**Expected Output:**
```
k3s version v1.29.0+k3s1 (12345678)
go version go1.21.6
```

### Configure kubectl Access

```bash
# k3s automatically installs kubectl and configures kubeconfig
# Verify kubectl can communicate with the cluster
kubectl get nodes

# Expected output:
# NAME         STATUS   ROLES                  AGE   VERSION
# gpu-node-1   Ready    control-plane,master   10s   v1.29.0+k3s1
```

### Verify Docker Runtime in k3s

```bash
# Check that k3s is using Docker runtime
sudo crictl info | grep "runtime"

# Expected output should include docker
```

### Verify GPU Device Visibility on Node

```bash
# Check that the GPU device is visible on the node
kubectl describe node gpu-node-1 | grep -A 10 "Allocatable"
```

**Expected Output (before device plugin):**
```
Allocatable:
  cpu:                16
  ephemeral-storage:  123456789Ki
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  memory:             32888888Ki
  pods:               110
```

**Note:** At this stage, `nvidia.com/gpu` will not appear in the allocatable resources. This is expected and will be addressed in the next document when we deploy the NVIDIA Device Plugin.

---

## Step 5: Install Helm (Package Manager)

Helm is required for deploying the NVIDIA Device Plugin and observability stack.

```bash
# Download Helm installation script
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify Helm installation
helm version
```

**Expected Output:**
```
version.BuildInfo{Version:"v3.15.0", ...}
```

### Add Required Helm Repositories

```bash
# Add NVIDIA Helm repository (for device plugin)
helm repo add nvidia https://nvidia.github.io/k8s-device-plugin
helm repo update

# Add Prometheus Community repository (for kube-prometheus-stack)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Verify repositories
helm repo list
```

**Expected Output:**
```
NAME                    URL
nvidia                  https://nvidia.github.io/k8s-device-plugin
prometheus-community    https://prometheus-community.github.io/helm-charts
```

---

## Step 6: Create Namespaces

Create the required namespaces for organized resource deployment:

```bash
# Create namespace for GPU infrastructure
kubectl create namespace gpu-infrastructure

# Create namespace for workloads
kubectl create namespace ml-workloads

# Create namespace for observability
kubectl create namespace monitoring

# Create namespace for ArgoCD (GitOps)
kubectl create namespace argocd

# Create namespace for MinIO (backup storage)
kubectl create namespace minio

# Verify namespaces
kubectl get namespaces
```

**Expected Output:**
```
NAME                  STATUS   AGE
argocd                Active   1s
default               Active   10m
gpu-infrastructure    Active   5s
kube-system           Active   10m
minio                 Active   0s
ml-workloads          Active   3s
monitoring            Active   2s
```

---

## Verification Checklist

Complete the following verification steps before proceeding to GPU Time-Slicing configuration:

### ✅ System-Level Verification

```bash
# 1. Verify NVIDIA driver is loaded
nvidia-smi
# Expected: GPU information displayed

# 2. Verify Docker is running with NVIDIA runtime
sudo docker info | grep -i "nvidia"
# Expected: nvidia runtime listed

# 3. Verify Docker GPU passthrough
docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi
# Expected: Same as host nvidia-smi

# 4. Verify k3s is running
sudo systemctl status k3s
# Expected: Active: active (running)

# 5. Verify kubectl access
kubectl get nodes
# Expected: gpu-node-1 in Ready state
```

### ✅ Kubernetes-Level Verification

```bash
# 6. Verify k3s is using Docker runtime
sudo crictl info | grep "Runtime"
# Expected: docker listed as runtime

# 7. Verify namespaces exist
kubectl get namespaces
# Expected: gpu-infrastructure, ml-workloads, monitoring present

# 8. Verify Helm repositories
helm repo list
# Expected: nvidia and prometheus-community repos listed
```

---

## Troubleshooting

### Issue: k3s fails to start after Docker installation

**Symptom:** `sudo systemctl status k3s` shows failed state.

**Solution:**
```bash
# Check k3s logs
sudo journalctl -u k3s -n 50

# If Docker socket permission issue:
sudo chmod 666 /var/run/docker.sock
sudo systemctl restart k3s
```

### Issue: Docker cannot access GPU

**Symptom:** `docker run --gpus all` fails with "could not select device driver".

**Solution:**
```bash
# Reconfigure NVIDIA runtime
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verify configuration
cat /etc/docker/daemon.json
# Should contain: "runtimes": {"nvidia": {"path": "nvidia-container-runtime"}}
```

### Issue: kubectl command not found

**Symptom:** `kubectl: command not found`

**Solution:**
```bash
# k3s installs kubectl to /usr/local/bin
# Add to PATH if not present
echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
source ~/.bashrc
```

### Issue: GPU not visible after reboot

**Symptom:** `nvidia-smi` fails with "command not found" or driver errors.

**Solution:**
```bash
# Check if NVIDIA driver module is loaded
lsmod | grep nvidia

# If not loaded, reinstall driver
sudo apt-get install --reinstall nvidia-driver-535
sudo reboot
```

---

## Next Steps

With infrastructure setup complete, proceed to:

**Document 2:** `02-gpu-time-slicing-config.md`

This document covers:
- Deploying the NVIDIA Device Plugin via Helm
- Configuring Time-Slicing to split 1 GPU into 4 replicas
- Verifying that the Kubernetes scheduler recognizes the logical GPU replicas
