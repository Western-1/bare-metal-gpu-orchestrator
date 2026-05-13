#!/bin/bash
set -e

echo "=========================================================="
echo " SECURE DATA WIPE UTILITY"
echo " WARNING: This will permanently destroy all K3s state,"
echo " ML models, and configurations on this server."
echo "=========================================================="
read -p "Are you absolutely sure you want to proceed? (yes/N): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Aborting."
    exit 1
fi

echo "[INFO] Uninstalling K3s cluster gracefully..."
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    /usr/local/bin/k3s-uninstall.sh || true
else
    echo "[WARN] K3s uninstaller not found, skipping."
fi

echo "[INFO] Stopping Tailscale..."
sudo systemctl stop tailscaled || true

echo "[INFO] Securely shredding K3s secrets and configurations..."
# We use shred instead of rm to physically overwrite data on the disk
if [ -d "/etc/rancher" ]; then
    find /etc/rancher -type f -exec sudo shred -u -n 3 {} \; || true
    sudo rm -rf /etc/rancher || true
fi

if [ -d "/var/lib/rancher/k3s" ]; then
    echo "Shredding K3s state directory (this may take a moment)..."
    find /var/lib/rancher/k3s -type f -exec sudo shred -u -n 3 {} \; || true
    sudo rm -rf /var/lib/rancher/k3s || true
fi

echo "[INFO] Securely shredding ML model cache..."
if [ -d "/mnt/nvme/huggingface-cache" ]; then
    echo "Shredding Hugging Face models..."
    find /mnt/nvme/huggingface-cache -type f -exec sudo shred -u -n 1 {} \; || true
    sudo rm -rf /mnt/nvme/huggingface-cache || true
fi

echo "[INFO] Shredding bash history..."
cat /dev/null > ~/.bash_history && history -c || true
sudo shred -u ~/.bash_history || true

echo "=========================================================="
echo "[SUCCESS] Secure wipe complete. The server is now clean and"
echo "ready to be returned to the hosting provider."
echo "=========================================================="
