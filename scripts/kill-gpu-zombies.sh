#!/bin/bash
# ==============================================================================
# GPU Zombie Process Killer
# Automatically finds and kills orphaned Python processes holding GPU VRAM.
# ==============================================================================

echo "[INFO] Scanning for zombie GPU processes..."

# Find all python processes running on NVIDIA GPUs
ZOMBIES=$(fuser -v /dev/nvidia* 2>/dev/null | grep -i python | awk '{print $2}')

if [ -z "$ZOMBIES" ]; then
    echo "[SUCCESS] No zombie GPU processes found. VRAM is clean."
    exit 0
fi

echo "[WARN] Found potential zombie processes holding VRAM:"
for PID in $ZOMBIES; do
    echo "  - Killing PID: $PID"
    sudo kill -9 $PID
done

echo "[SUCCESS] All GPU zombie processes have been terminated."
