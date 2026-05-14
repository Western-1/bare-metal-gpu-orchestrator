# Hardware Power Optimization and GreenOps

**Component:** NVIDIA Power Management  
**Objective:** Optimize thermal efficiency for 24/7 Time-Sliced inference  
**GPU Model:** NVIDIA RTX 5070 Ti (Blackwell Architecture)  

---

## Prerequisites

Verify operational status of the GPU:

```bash
nvidia-smi
nvidia-smi -q -d POWER
```

---

## Step 1: GreenOps Overview

### Environmental and Operational Considerations

Running ML inference 24/7 on consumer GPUs requires strict thermal management:

- **Power Consumption:** The RTX 5070 Ti operates at a 300W TDP, utilizing ~7.2 kWh/day at peak load.
- **Thermal Dissipation:** 300W of heat generation significantly increases ambient HVAC load.
- **Carbon Footprint:** Standard grid electricity averages 0.4 kg CO2/kWh globally.
- **Hardware Longevity:** Sustained high temperatures (>75°C) accelerate silicon degradation and fan bearing failure.

### Power Cap Strategy

This strategy enforces a strict power limit to maximize performance-per-watt:

- **Power Cap:** Restrict GPU power draw to 220W (73% of TDP).
- **Thermal Targets:** Target sustained operating temperatures < 70°C.
- **Performance Impact:** < 5% latency increase for a 27% power reduction.

### Efficiency Baseline

| **Configuration** | **Power Draw** | **Relative Performance** | **Temperature Target** |
|--------------------|----------------|--------------------------|------------------------|
| **Default** | 300W | 100% | 75-82°C |
| **Optimized** | 220W | 95% | 65-72°C |
| **Conservative** | 180W | 85% | 60-68°C |

**Recommendation:** A 220W power cap yields the optimal balance of inference throughput, energy efficiency, and thermal stability.

---

## Step 2: Establish Power Baseline

### Query Current Limits

```bash
nvidia-smi -q -d POWER
```

### Telemetry Under Load

Initialize a sustained load test (e.g., Locust) and monitor hardware telemetry:

```bash
watch -n 1 'nvidia-smi --query-gpu=power.draw,power.limit,temperature.gpu,utilization.gpu --format=csv,noheader,nounits'
```

---

## Step 3: Enforce Power Limits

### Temporary Enforcement (Session)

```bash
sudo nvidia-smi -pl 220
nvidia-smi --query-gpu=power.limit --format=csv,noheader
```

### Persistent Enforcement (Systemd)

To persist power constraints across system reboots, configure a systemd oneshot service:

```bash
cat <<EOF | sudo tee /etc/systemd/system/nvidia-power-limit.service
[Unit]
Description=Set NVIDIA GPU Power Limit
After=multi-user.target
ConditionPathExists=/dev/nvidia0

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -pm 1
ExecStart=/usr/bin/nvidia-smi -pl 220

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now nvidia-power-limit.service
sudo systemctl status nvidia-power-limit.service
```

---

## Step 4: Configure Thermal Targets

The RTX 5070 Ti supports dynamic hardware throttling based on temperature ceilings.

```bash
sudo nvidia-smi -tg 70
nvidia-smi --query-gpu=temperature.gpu.target --format=csv,noheader
```

Automatic fan control is recommended for standard environments:

```bash
sudo nvidia-smi -acp 1
nvidia-smi -q | grep "Fan Control"
```

---

## Step 5: Validate Performance Impact

Execute sequential API benchmarks to quantify the latency impact of the 220W limit.

```bash
# Terminal 1: Port-forward
kubectl port-forward -n ml-workloads svc/embedding-service 8000:8000

# Terminal 2: Execute benchmark
for i in {1..100}; do
  curl -w "\nTime: %{time_total}s\n" -s -o /dev/null \
    -X POST http://localhost:8000/embed \
    -H "Content-Type: application/json" \
    -d '{"text":"benchmark payload"}'
done | grep "Time:" | awk '{sum+=$2; count++} END {print "Average:", sum/count, "s"}'
```

---

## Step 6: Power Profiling Automation

Create localized scripts to toggle states dynamically.

```bash
sudo mkdir -p /usr/local/bin/gpu-power-profiles

# 300W Performance
cat <<EOF | sudo tee /usr/local/bin/gpu-power-profiles/performance.sh
#!/bin/bash
sudo nvidia-smi -pl 300
EOF

# 220W Balanced
cat <<EOF | sudo tee /usr/local/bin/gpu-power-profiles/balanced.sh
#!/bin/bash
sudo nvidia-smi -pl 220
EOF

# 180W Eco
cat <<EOF | sudo tee /usr/local/bin/gpu-power-profiles/eco.sh
#!/bin/bash
sudo nvidia-smi -pl 180
EOF

sudo chmod +x /usr/local/bin/gpu-power-profiles/*.sh
```

### Scheduled Transitions (Optional)

Configure crontab to drop into eco mode during off-peak hours:

```bash
# sudo crontab -e
# 0 8 * * * /usr/local/bin/gpu-power-profiles/balanced.sh
# 0 20 * * * /usr/local/bin/gpu-power-profiles/eco.sh
```

---

## Step 7: Prometheus and Grafana Integration

Query DCGM power telemetry directly:

```bash
kubectl port-forward -n monitoring daemonset/dcgm-exporter 9400:9400 &
curl -s http://localhost:9400/metrics | grep DCGM_FI_DEV_POWER_USAGE
```

### Alerting Rules

Inject the following into the Prometheus `gpu-alerting-rules` ConfigMap:

```yaml
- alert: HighPowerUsage
  expr: DCGM_FI_DEV_POWER_USAGE{GPU="0"} / 1000 > 250
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "GPU power usage exceeds 250W. Verify power cap configuration."

- alert: PowerLimitViolation
  expr: DCGM_FI_DEV_POWER_USAGE{GPU="0"} > DCGM_FI_DEV_POWER_LIMIT{GPU="0"}
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "GPU power draw exceeds hardware limit boundary."
```

---

## Step 8: Calculate Energy Savings

- **Default (300W, 24/7):** 7.2 kWh/day
- **Optimized (220W, 24/7):** 5.28 kWh/day
- **Delta:** 1.92 kWh/day (700.8 kWh/year)

### Operational ROI

| **Metric** | **Default (300W)** | **Optimized (220W)** | **Delta** |
|------------|-------------------|---------------------|-------------|
| **Annual Energy** | 2,628 kWh | 1,927.2 kWh | 700.8 kWh |
| **Annual Cost (@ $0.12/kWh)** | $315.36 | $231.26 | $84.10 |
| **Annual CO2** | 1,051 kg | 771 kg | 280 kg |

---

## Troubleshooting

### Persistence Failure Across Reboots
If `nvidia-smi` reports 300W after a reboot:
1. Verify systemd execution: `sudo systemctl status nvidia-power-limit.service`.
2. Ensure `/dev/nvidia0` is available at boot (driver loaded).

### Excessive Thermal Throttling
If `nvidia-smi -q | grep "Clocks Throttle Reasons"` shows `SW Power Cap`:
- The power limit is actively suppressing clocks (expected behavior under load).
If it shows `HW Thermal Slowdown`:
- Fan speed is insufficient or ambient temperature is too high. Increase cooling or lower the power cap.

---

## Next Steps

Proceed to `09-security-and-network-isolation.md` to establish workload isolation topologies and NetworkPolicies.
