#!/bin/bash
# ==============================================================================
# HuggingFace Model Cache Downloader
# Pre-downloads heavy models to a local directory so Docker containers start instantly.
# ==============================================================================

export HF_HUB_ENABLE_HF_TRANSFER=1
CACHE_DIR="$(pwd)/.cache/models"

echo "[INFO] Creating local model cache directory at $CACHE_DIR..."
mkdir -p "$CACHE_DIR"

echo "[INFO] Ensure you have huggingface_hub and hf_transfer installed locally:"
echo "       uv pip install huggingface_hub hf_transfer"

echo "[INFO] Downloading commonly used models..."

# Example: Download a small embedding model to prepopulate the cache
# huggingface-cli download sentence-transformers/all-MiniLM-L6-v2 --cache-dir "$CACHE_DIR"

echo "[SUCCESS] Cache directory is ready. Docker will mount it automatically."
