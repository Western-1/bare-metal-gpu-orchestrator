#!/bin/bash
set -e

echo "=========================================================="
echo " Tailscale Zero Trust Setup for Bare-Metal Server"
echo "=========================================================="

# 1. Install Tailscale
echo "[INFO] Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# 2. Authenticate
if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    echo "[WARN] TAILSCALE_AUTH_KEY is not set. You will need to authenticate manually."
    sudo tailscale up --ssh
else
    echo "[INFO] Authenticating Tailscale automatically..."
    sudo tailscale up --authkey=${TAILSCALE_AUTH_KEY} --ssh
fi

# 3. Configure UFW (Uncomplicated Firewall) for Zero Trust
echo "[INFO] Configuring UFW Firewall Rules..."

# Allow Tailscale interface to do anything
sudo ufw allow in on tailscale0
sudo ufw allow out on tailscale0

# Deny SSH and K8s API on the public internet interface (assuming eth0 or similar)
# We will use explicit deny rules to ensure safety
sudo ufw deny 22/tcp
sudo ufw deny 6443/tcp

# Ensure UFW is enabled
echo "y" | sudo ufw enable

echo "=========================================================="
echo "[SUCCESS] Tailscale is running and UFW is locked down."
echo "Your server can now only be accessed via SSH using its Tailscale IP."
echo "Run 'tailscale ip -4' to see your private IP."
echo "=========================================================="
