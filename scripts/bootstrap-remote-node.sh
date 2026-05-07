#!/bin/bash
# -----------------------------------------------------------------------------
# Bootstrap Remote Node for Bare-Metal GPU Deployments
# Architecture: k3s + containerd + NVIDIA Time-Slicing
# Author: Principal MLOps Engineer
# -----------------------------------------------------------------------------

set -eo pipefail

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Must run as root
if [ "$EUID" -ne 0 ]; then
  log_err "Please run as root (use sudo)"
fi

log_info "Starting remote node bootstrap process..."

# 1. Update and install prerequisites
log_info "Updating system and installing prerequisites..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
apt-get install -y curl wget git jq vim htop nvme-cli build-essential

# 2. Install NVIDIA Drivers (if not installed)
if command -v nvidia-smi &> /dev/null; then
    log_info "NVIDIA drivers already installed. Skipping..."
else
    log_info "Installing NVIDIA drivers (headless)..."
    apt-get install -y linux-headers-$(uname -r)
    apt-get install -y nvidia-driver-535-server nvidia-utils-535-server
    log_warn "NVIDIA drivers installed. A reboot is highly recommended after bootstrap."
fi

# 3. Install NVIDIA Container Toolkit
log_info "Setting up NVIDIA Container Toolkit repository..."
if [ ! -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg ]; then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
      sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
      sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update -y
fi

log_info "Installing NVIDIA Container Toolkit..."
apt-get install -y nvidia-container-toolkit

# 4. Install k3s (with containerd)
log_info "Installing k3s (defaulting to containerd)..."
if command -v k3s &> /dev/null; then
    log_info "k3s is already installed. Skipping..."
else
    # Install k3s. We DO NOT use --docker here, sticking to native containerd.
    curl -sfL https://get.k3s.io | sh -s - \
      --write-kubeconfig-mode 644 \
      --disable traefik \
      --disable servicelb
    
    # Wait for k3s to be fully ready
    sleep 10
fi

# 5. Configure containerd for NVIDIA Runtime
log_info "Configuring containerd for NVIDIA runtime..."
# k3s uses a custom config template for containerd
mkdir -p /var/lib/rancher/k3s/agent/etc/containerd
cp /var/lib/rancher/k3s/agent/etc/containerd/config.toml /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl 2>/dev/null || true

# We generate the NVIDIA runtime config for k3s containerd template
cat <<EOF > /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
[plugins.opt]
  path = "/var/lib/rancher/k3s/agent/containerd"

[plugins."io.containerd.grpc.v1.cri"]
  stream_server_address = "127.0.0.1"
  stream_server_port = "10010"
  enable_selinux = false
  enable_unprivileged_ports = true
  enable_unprivileged_icmp = true
  sandbox_image = "rancher/mirrored-pause:3.6"

[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = "overlayfs"
  disable_snapshot_annotations = true

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  SystemdCgroup = true

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  privileged_without_host_devices = false
  runtime_engine = ""
  runtime_root = ""
  runtime_type = "io.containerd.runc.v2"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
  BinaryName = "/usr/bin/nvidia-container-runtime"
  SystemdCgroup = true
EOF

log_info "Restarting k3s to apply containerd configuration..."
systemctl restart k3s

# 6. Setup Basic System Monitoring (sysstat, htop)
log_info "Setting up host-level monitoring..."
apt-get install -y sysstat
sed -i 's/ENABLED="false"/ENABLED="true"/g' /etc/default/sysstat
systemctl enable --now sysstat

# Verify Installation
log_info "Validating installation..."
if k3s kubectl get nodes | grep -q "Ready"; then
    log_info "k3s node is Ready."
else
    log_warn "k3s node is not yet Ready, but installation completed."
fi

log_info "Bootstrap complete! You can now apply the Time-Slicing ConfigMap and NVIDIA Device Plugin."
log_info "Ensure you reboot the server if NVIDIA drivers were freshly installed."
