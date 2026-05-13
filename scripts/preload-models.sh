#!/bin/bash
set -e

echo "=========================================================="
echo " MODEL PRELOADER (via Rclone)"
echo " Downloads models from S3/R2 directly to NVMe before boot"
echo "=========================================================="

CACHE_DIR="/mnt/nvme/huggingface-cache"
REMOTE_SOURCE="my-s3:ml-models-bucket/huggingface-cache/"

# 1. Install rclone if missing
if ! command -v rclone &> /dev/null; then
    echo "[INFO] Installing rclone..."
    sudo -v ; curl https://rclone.org/install.sh | sudo bash
fi

# 2. Ensure cache directory exists
sudo mkdir -p $CACHE_DIR
sudo chown -R 1000:1000 $CACHE_DIR

# 3. Download Models
echo "[INFO] Syncing models from $REMOTE_SOURCE to $CACHE_DIR..."
echo "This will use 16 parallel threads for maximum bandwidth."

# We assume rclone is configured (e.g. ~/.config/rclone/rclone.conf exists)
# or env vars are set (RCLONE_CONFIG_MY_S3_TYPE=s3, etc.)
sudo -u '#1000' rclone sync $REMOTE_SOURCE $CACHE_DIR \
    --transfers 16 \
    --checkers 16 \
    --s3-chunk-size 64M \
    --fast-list \
    --progress

echo "=========================================================="
echo "[SUCCESS] Models pre-loaded successfully. Pods will now"
echo "experience instant startup times."
echo "=========================================================="
