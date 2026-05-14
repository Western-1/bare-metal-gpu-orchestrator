# Infrastructure Setup: Bare-Metal Node Preparation

**Target OS:** Ubuntu 24.04 LTS  
**Hardware:** AMD Ryzen 7 7800X3D, NVIDIA RTX 5070 Ti (16GB), 32GB RAM  
**Purpose:** Prepare the bare-metal node for k3s with containerd and GPU passthrough.

---

## System Verification and Preparation

Verify the hardware specifications:

```bash
# Check CPU cores and threads
lscpu | grep "^CPU(s):"

# Check total system RAM
free -h | grep "Mem:"

# Check GPU presence and VRAM
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
```

Update the OS and install required dependencies:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git ca-certificates gnupg lsb-release
```

---

## Step 1: NVIDIA Driver Installation

Remove existing conflicting packages:

```bash
sudo apt purge -y nvidia* libcuda* libnvidia*
sudo apt autoremove -y
```

Install NVIDIA driver (version 535+ is required for CUDA 12.x support):

```bash
sudo add-apt-repository ppa:graphics-drivers/ppa -y
sudo apt update
sudo apt install -y nvidia-driver-535
sudo reboot
```

Verify driver initialization:

```bash
nvidia-smi
nvidia-smi | grep "CUDA Version"
```

---

## Step 2: NVIDIA Container Toolkit Configuration

Add the NVIDIA repository:

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
```

Install the toolkit:

```bash
sudo apt-get install -y nvidia-container-toolkit
nvidia-container-cli --version
```

Configure containerd to utilize the NVIDIA runtime:

```bash
sudo nvidia-ctk runtime configure --runtime=containerd
sudo systemctl restart k3s
```

Verify containerd configuration:

```bash
sudo cat /etc/containerd/config.toml | grep -A 5 "nvidia-container-runtime"
```

---

## Step 3: k3s Installation (containerd Runtime)

Install k3s as a single-node cluster:

```bash
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --disable servicelb \
  --node-name gpu-node-1 \
  --write-kubeconfig-mode 644 \
  --tls-san gpu-node-1
```

**Configuration Details:**
- `--disable traefik / servicelb`: Disables default ingress/loadbalancer. NGINX will be utilized.
- `--node-name gpu-node-1`: Explicit scheduling identifier.
- `--write-kubeconfig-mode 644`: Provides standard user read access to kubeconfig.

Verify cluster state:

```bash
sudo systemctl status k3s
k3s --version
kubectl get nodes
```

Check the active runtime (expected: containerd):

```bash
sudo crictl info | grep "Runtime"
```

Check allocatable resources:

```bash
kubectl describe node gpu-node-1 | grep -A 10 "Allocatable"
```
*Note: `nvidia.com/gpu` will not be present until the Device Plugin is deployed in Step 02.*

---

## Step 4: Helm Installation

Install Helm for deploying Kubernetes packages:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

Register standard repositories:

```bash
helm repo add nvidia https://nvidia.github.io/k8s-device-plugin
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm repo list
```

---

## Step 5: Namespace Provisioning

Create isolated namespaces for the infrastructure components:

```bash
kubectl create namespace gpu-infrastructure
kubectl create namespace ml-workloads
kubectl create namespace monitoring
kubectl create namespace argocd
kubectl create namespace minio
kubectl get namespaces
```

---

## Verification Checklist

Execute the following commands to validate the environment state:

### System-Level Verification

```bash
# 1. Verify NVIDIA driver
nvidia-smi

# 2. Verify containerd runtime configuration
sudo cat /etc/containerd/config.toml | grep -A 5 "nvidia-container-runtime"

# 3. Verify k3s service
sudo systemctl status k3s

# 4. Verify node status
kubectl get nodes
```

### Kubernetes-Level Verification

```bash
# 5. Verify k3s runtime
sudo crictl info | grep "Runtime"

# 6. Verify namespaces
kubectl get namespaces

# 7. Verify Helm repositories
helm repo list
```

---

## Troubleshooting

### k3s Process Failure
**Symptom:** `systemctl status k3s` returns failed state.
**Resolution:** Rebuild the containerd config.
```bash
sudo nvidia-ctk runtime configure --runtime=containerd
sudo systemctl restart k3s
```

### Missing GPU Resources
**Symptom:** Pod requests for `nvidia.com/gpu` fail.
**Resolution:** Verify containerd configuration overrides.
```bash
sudo cat /etc/containerd/config.toml | grep -A 5 "nvidia-container-runtime"
sudo systemctl restart k3s
```

### Unrecognized kubectl Command
**Symptom:** `kubectl: command not found`.
**Resolution:** Add the binary path to `.bashrc`.
```bash
echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
source ~/.bashrc
```

---

## Next Steps

Proceed to `02-gpu-time-slicing-config.md` to deploy the NVIDIA Device Plugin and define the time-slicing ConfigMap.
