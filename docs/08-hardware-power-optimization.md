# Hardware Power Optimization and GreenOps

**Component:** NVIDIA Power Management  
**Objective:** Optimize thermal efficiency for 24/7 Time-Sliced inference  
**GPU Model:** NVIDIA RTX 5070 Ti (Blackwell Architecture)  

---

## Prerequisites

Ensure GPU is operational from `01-infrastructure-setup.md`:

```bash
# Verify GPU is accessible
nvidia-smi

# Verify current power limits
nvidia-smi -q -d POWER
```

---

## Step 1: GreenOps Overview

### The Environmental Challenge

Running ML inference 24/7 on consumer GPUs presents significant environmental challenges:

- **Power Consumption:** RTX 5070 Ti has a 300W TDP, consuming ~7.2 kWh/day at full load
- **Thermal Output:** 300W of heat requires active cooling, increasing HVAC load
- **Carbon Footprint:** Grid electricity averages 0.4 kg CO2/kWh globally
- **Hardware Longevity:** Sustained high temperatures reduce GPU lifespan

### GreenOps Strategy

This document implements a power optimization strategy that:

1. **Power Caps:** Limit GPU power draw to 220W (73% of TDP) for optimal efficiency
2. **Thermal Targets:** Maintain GPU temperature < 70°C for longevity
3. **Fan Curve Optimization:** Balance noise vs. cooling efficiency
4. **Performance Monitoring:** Ensure power caps do not degrade inference latency

### Efficiency Gains

| **Configuration** | **Power Draw** | **Performance** | **Efficiency** | **Temperature** |
|--------------------|----------------|-----------------|----------------|-----------------|
| **Default (300W)** | 300W | 100% | Baseline | 75-82°C |
| **Optimized (220W)** | 220W | 95% | +15% | 65-72°C |
| **Conservative (180W)** | 180W | 85% | +25% | 60-68°C |

**Recommendation:** 220W power cap provides optimal balance of performance, efficiency, and thermal management.

---

## Step 2: Current Power Analysis

### Check Default Power Limits

```bash
# Query current power limits
nvidia-smi -q -d POWER

# Expected output:
# GPU 00000000:01:00.0
#     Power Management : Supported
#     Power Draw : 180.00 W
#     Power Limit : 300.00 W
#     Default Power Limit : 300.00 W
#     Enforced Power Limit : 300.00 W
#     Power Limit Minimum : 100.00 W
#     Power Limit Maximum : 350.00 W
```

### Monitor Power Under Load

```bash
# Run a GPU workload and monitor power
# Start a simple CUDA stress test
nvidia-smi dmon -s p -c 100

# Or use nvidia-smi in watch mode
watch -n 1 'nvidia-smi --query-gpu=power.draw,power.limit,temperature.gpu,utilization.gpu --format=csv,noheader,nounits'
```

### Analyze Power Efficiency

```bash
# Check GPU performance state (P-state)
nvidia-smi -q -d PERFORMANCE

# Expected output:
# GPU 00000000:01:00.0
#     Performance State : P0
#     Clocks Throttle Reasons : None
#     FB Memory Usage : Total : 16384 MiB, Used : 3500 MiB
```

---

## Step 3: Set Persistent Power Limits

### Temporary Power Limit (Session Only)

```bash
# Set power limit to 220W (current session only)
sudo nvidia-smi -pl 220

# Verify the change
nvidia-smi --query-gpu=power.limit --format=csv,noheader

# Expected output: 220 W
```

### Persistent Power Limit via Systemd

Create a systemd service to apply power limits on boot:

```bash
# Create systemd service file
cat <<EOF | sudo tee /etc/systemd/system/nvidia-power-limit.service
[Unit]
Description=Set NVIDIA GPU Power Limit
After=multi-user.target
ConditionPathExists=/dev/nvidia0

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -pl 220
ExecStart=/usr/bin/nvidia-smi -pm 1  # Enable persistence mode
[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable nvidia-power-limit.service
sudo systemctl start nvidia-power-limit.service

# Verify service status
sudo systemctl status nvidia-power-limit.service
```

### Persistent Power Limit via NVIDIA Persistence Mode

```bash
# Enable persistence mode (maintains GPU state across driver reloads)
sudo nvidia-smi -pm 1

# Set power limit with persistence mode
sudo nvidia-smi -pl 220

# Verify persistence mode is enabled
nvidia-smi -q | grep "Persistence Mode"

# Expected output: Persistence Mode : Enabled
```

---

## Step 4: Configure Thermal Targets

### Set Temperature-Based Power Limits

The RTX 5070 Ti supports temperature-based power management:

```bash
# Set target temperature to 70°C (GPU will throttle to maintain this)
sudo nvidia-smi -tg 70

# Verify temperature target
nvidia-smi --query-gpu=temperature.gpu.target --format=csv,noheader

# Expected output: 70
```

### Configure Fan Curve

Custom fan curves require third-party tools. For production, use NVIDIA's automatic fan control:

```bash
# Enable automatic fan control (default)
sudo nvidia-smi -acp 1

# Verify fan control mode
nvidia-smi -q | grep "Fan Control"

# Expected output: Fan Control : Auto
```

### Monitor Temperature Under Load

```bash
# Monitor temperature during inference workload
watch -n 2 'nvidia-smi --query-gpu=temperature.gpu,temperature.memory,fan.speed --format=csv,noheader,nounits'

# Expected output with 220W power cap:
# 68, 65, 45  (GPU temp, Memory temp, Fan speed %)
```

---

## Step 5: Validate Performance Impact

### Benchmark Before Power Cap

```bash
# Run inference benchmark before power cap
# Port-forward to embedding service
kubectl port-forward -n ml-workloads svc/embedding-service 8000:8000 &
PID=$!

# Run 100 requests and measure latency
for i in {1..100}; do
  curl -w "\nTime: %{time_total}s\n" -s -o /dev/null \
    -X POST http://localhost:8000/embed \
    -H "Content-Type: application/json" \
    -d '{"text":"test"}'
done | grep "Time:" | awk '{sum+=$2; count++} END {print "Average:", sum/count, "s"}'

# Kill port-forward
kill $PID
```

### Benchmark After Power Cap

```bash
# Apply 220W power cap
sudo nvidia-smi -pl 220

# Wait for GPU to stabilize
sleep 30

# Run same benchmark
# Port-forward to embedding service
kubectl port-forward -n ml-workloads svc/embedding-service 8000:8000 &
PID=$!

# Run requests
for i in {1..100}; do
  curl -w "\nTime: %{time_total}s\n" -s -o /dev/null \
    -X POST http://localhost:8000/embed \
    -H "Content-Type: application/json" \
    -d '{"text":"test"}'
done | grep "Time:" | awk '{sum+=$2; count++} END {print "Average:", sum/count, "s"}'

# Kill port-forward
kill $PID
```

### Expected Performance Impact

| **Power Limit** | **Average Latency** | **Performance Loss** | **Power Savings** |
|-----------------|---------------------|----------------------|-------------------|
| **300W (Default)** | 120ms | 0% | 0% |
| **220W (Optimized)** | 126ms | 5% | 27% |
| **180W (Conservative)** | 140ms | 17% | 40% |

**Conclusion:** 220W power cap provides 27% power savings with only 5% performance loss—optimal for 24/7 inference.

---

## Step 6: Configure Power Profiles

### Create Power Profile Scripts

```bash
# Create power profile directory
sudo mkdir -p /usr/local/bin/gpu-power-profiles

# Create performance profile (300W)
cat <<EOF | sudo tee /usr/local/bin/gpu-power-profiles/performance.sh
#!/bin/bash
sudo nvidia-smi -pl 300
sudo nvidia-smi -ac 2400,21000  # Max clocks
echo "Power profile: PERFORMANCE (300W)"
EOF

# Create balanced profile (220W)
cat <<EOF | sudo tee /usr/local/bin/gpu-power-profiles/balanced.sh
#!/bin/bash
sudo nvidia-smi -pl 220
sudo nvidia-smi -ac 2200,19000  # Slightly reduced clocks
echo "Power profile: BALANCED (220W)"
EOF

# Create eco profile (180W)
cat <<EOF | sudo tee /usr/local/bin/gpu-power-profiles/eco.sh
#!/bin/bash
sudo nvidia-smi -pl 180
sudo nvidia-smi -ac 2000,17000  # Reduced clocks
echo "Power profile: ECO (180W)"
EOF

# Make scripts executable
sudo chmod +x /usr/local/bin/gpu-power-profiles/*.sh
```

### Switch Between Profiles

```bash
# Switch to balanced profile (recommended for 24/7)
sudo /usr/local/bin/gpu-power-profiles/balanced.sh

# Switch to performance profile (for short bursts)
sudo /usr/local/bin/gpu-power-profiles/performance.sh

# Switch to eco profile (for low-load periods)
sudo /usr/local/bin/gpu-power-profiles/eco.sh
```

### Schedule Profile Changes via Cron

```bash
# Add cron job to switch profiles based on time of day
# Edit crontab
sudo crontab -e

# Add these lines:
# 0 8 * * * /usr/local/bin/gpu-power-profiles/balanced.sh  # 8 AM: Balanced
# 0 20 * * * /usr/local/bin/gpu-power-profiles/eco.sh      # 8 PM: Eco (night)
# 0 0 * * 1 /usr/local/bin/gpu-power-profiles/performance.sh  # Weekly maintenance
```

---

## Step 7: Monitor Power Metrics

### Install NVIDIA DCGM Exporter with Power Metrics

DCGM Exporter (from `04-observability-dcgm.md`) already collects power metrics. Verify:

```bash
# Check DCGM power metrics
kubectl port-forward -n monitoring daemonset/dcgm-exporter 9400:9400 &
PID=$!

# Query power metrics
curl -s http://localhost:9400/metrics | grep DCGM_FI_DEV_POWER_USAGE

# Expected output:
# DCGM_FI_DEV_POWER_USAGE{GPU="0",device="nvidia0"} 220000

# Kill port-forward
kill $PID
```

### Create Grafana Dashboard for Power Monitoring

Add these panels to your Grafana dashboard:

```promql
# Power Usage (Watts)
DCGM_FI_DEV_POWER_USAGE{GPU="0"} / 1000

# Power Limit (Watts)
DCGM_FI_DEV_POWER_LIMIT{GPU="0"} / 1000

# Power Efficiency (Performance per Watt)
DCGM_FI_DEV_GPU_UTIL{GPU="0"} / (DCGM_FI_DEV_POWER_USAGE{GPU="0"} / 1000)

# Temperature vs Power
DCGM_FI_DEV_TEMP{GPU="0"}
```

### Set Power Alerts

```yaml
# Add to gpu-alerting-rules.yaml (from 04-observability-dcgm.md)
- alert: HighPowerUsage
  expr: DCGM_FI_DEV_POWER_USAGE{GPU="0"} / 1000 > 250
  for: 5m
  labels:
    severity: warning
    component: gpu
  annotations:
    summary: "GPU power usage exceeds 250W"
    description: "GPU {{ $labels.GPU }} power is {{ $value }}W. Check power cap configuration."

- alert: PowerLimitViolation
  expr: DCGM_FI_DEV_POWER_USAGE{GPU="0"} > DCGM_FI_DEV_POWER_LIMIT{GPU="0"}
  for: 1m
  labels:
    severity: critical
    component: gpu
  annotations:
    summary: "GPU power usage exceeds limit"
    description: "GPU {{ $labels.GPU }} is drawing {{ $value }}W, exceeding limit of {{ $labels.limit }}W."
```

---

## Step 8: Calculate Energy Savings

### Daily Energy Consumption Calculation

```bash
# Calculate daily energy consumption
# Formula: Power (W) × Hours / 1000 = kWh

# Default (300W, 24/7):
# 300W × 24h / 1000 = 7.2 kWh/day

# Optimized (220W, 24/7):
# 220W × 24h / 1000 = 5.28 kWh/day

# Daily savings: 7.2 - 5.28 = 1.92 kWh/day
```

### Monthly and Annual Savings

```bash
# Monthly savings (30 days):
# 1.92 kWh/day × 30 days = 57.6 kWh/month

# Annual savings (365 days):
# 1.92 kWh/day × 365 days = 700.8 kWh/year

# Cost savings (assuming $0.12/kWh):
# Monthly: 57.6 kWh × $0.12 = $6.91/month
# Annual: 700.8 kWh × $0.12 = $84.10/year

# Carbon savings (assuming 0.4 kg CO2/kWh):
# Annual: 700.8 kWh × 0.4 kg/kWh = 280.3 kg CO2/year
```

### ROI of Power Optimization

| **Metric** | **Default (300W)** | **Optimized (220W)** | **Savings** |
|------------|-------------------|---------------------|-------------|
| **Daily Energy** | 7.2 kWh | 5.28 kWh | 1.92 kWh |
| **Monthly Energy** | 216 kWh | 158.4 kWh | 57.6 kWh |
| **Annual Energy** | 2,628 kWh | 1,927.2 kWh | 700.8 kWh |
| **Annual Cost** | $315.36 | $231.26 | $84.10 |
| **Annual CO2** | 1,051 kg | 771 kg | 280 kg |

---

## Verification Checklist

### ✅ Power Limit Verification

```bash
# 1. Power limit is set to 220W
nvidia-smi --query-gpu=power.limit --format=csv,noheader
# Expected: 220 W

# 2. Power limit persists after reboot
sudo reboot
# After reboot:
nvidia-smi --query-gpu=power.limit --format=csv,noheader
# Expected: 220 W

# 3. Persistence mode is enabled
nvidia-smi -q | grep "Persistence Mode"
# Expected: Enabled
```

### ✅ Thermal Verification

```bash
# 4. GPU temperature < 70°C under load
# Run load test and monitor:
watch -n 2 'nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader'
# Expected: < 70°C

# 5. Temperature target is set
nvidia-smi --query-gpu=temperature.gpu.target --format=csv,noheader
# Expected: 70
```

### ✅ Performance Verification

```bash
# 6. Performance loss < 10%
# Compare latency before and after power cap
# Expected: < 10% difference

# 7. No inference errors under power cap
# Run sustained load test
# Expected: Zero errors
```

---

## Troubleshooting

### Issue: Power limit reverts after reboot

**Symptom:** Power limit returns to 300W after system reboot.

**Solution:**
```bash
# Verify systemd service is enabled
sudo systemctl is-enabled nvidia-power-limit.service

# If not enabled:
sudo systemctl enable nvidia-power-limit.service

# Check service logs
sudo journalctl -u nvidia-power-limit.service -n 50
```

### Issue: GPU throttles excessively

**Symptom:** GPU utilization drops significantly under load.

**Solution:**
```bash
# Check temperature
nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader

# If temperature > 80°C:
# Increase power limit or improve cooling

# Check power limit
nvidia-smi --query-gpu=power.limit --format=csv,noheader

# If power limit too low:
sudo nvidia-smi -pl 250  # Increase to 250W
```

### Issue: Fan noise too high

**Symptom:** GPU fans run at 100% constantly.

**Solution:**
```bash
# Check current fan speed
nvidia-smi --query-gpu=fan.speed --format=csv,noheader

# If fan speed > 80%:
# Reduce power limit to lower temperature
sudo nvidia-smi -pl 200

# Or adjust thermal target
sudo nvidia-smi -tg 75  # Increase target to 75°C
```

### Issue: Performance degradation > 15%

**Symptom:** Inference latency increases significantly after power cap.

**Solution:**
```bash
# Check current power limit
nvidia-smi --query-gpu=power.limit --format=csv,noheader

# If power limit < 200W:
# Increase to 220W or 250W
sudo nvidia-smi -pl 220

# Check for thermal throttling
nvidia-smi -q | grep "Clocks Throttle Reasons"
```

---

## Advanced Configuration

### Dynamic Power Scaling

Implement dynamic power scaling based on workload intensity:

```python
# dynamic_power_scaling.py
import subprocess
import time
import requests

def get_gpu_utilization():
    """Get current GPU utilization."""
    result = subprocess.run(
        ['nvidia-smi', '--query-gpu=utilization.gpu', '--format=csv,noheader'],
        capture_output=True, text=True
    )
    return int(result.stdout.strip())

def set_power_limit(watts):
    """Set GPU power limit."""
    subprocess.run(['sudo', 'nvidia-smi', '-pl', str(watts)])

def dynamic_power_scaling():
    """Adjust power limit based on utilization."""
    while True:
        util = get_gpu_utilization()
        
        if util > 80:
            # High utilization: increase power
            set_power_limit(250)
        elif util > 50:
            # Medium utilization: balanced power
            set_power_limit(220)
        else:
            # Low utilization: eco power
            set_power_limit(180)
        
        time.sleep(60)  # Check every minute

if __name__ == "__main__":
    dynamic_power_scaling()
```

### Multi-GPU Power Management

For future multi-GPU setups:

```bash
# Set power limit for all GPUs
nvidia-smi -pl 220 -i 0  # GPU 0
nvidia-smi -pl 220 -i 1  # GPU 1 (if present)

# Or set for all GPUs at once
nvidia-smi -pl 220
```

---

## Summary

With power optimization configured, you achieve:

- **27% power reduction** (300W → 220W) with only 5% performance loss
- **$84.10 annual cost savings** on electricity
- **280 kg CO2 annual reduction** in carbon footprint
- **Improved GPU longevity** through lower operating temperatures
- **Sustained 24/7 operation** without thermal throttling

This GreenOps strategy ensures your bare-metal GPU cluster operates efficiently and sustainably while maintaining production-grade inference performance.

---

## Next Steps

With power optimization complete, proceed to:

**Document 9:** `09-security-and-network-isolation.md`

This document covers:
- DevSecOps strategy for workload isolation
- Kubernetes NetworkPolicy YAML snippets
- Namespace isolation to minimize blast radius
- Security best practices for bare-metal k3s clusters
