#!/bin/bash
sudo nvidia-smi -pl 220
sudo nvidia-smi -tg 70
sudo nvidia-smi -pm 1
echo "Power limit set to 220W, temperature target set to 70C."
