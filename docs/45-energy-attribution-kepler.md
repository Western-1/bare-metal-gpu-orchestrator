# Energy Attribution (Kepler GreenOps)

**Component:** Power Metrics  
**Objective:** Attribute exact energy consumption (Joules/Watts) to individual Kubernetes Pods  
**Architecture:** eBPF + Kepler + Prometheus  

---

## 1. The ESG and GreenOps Mandate

While `08-hardware-power-optimization.md` demonstrated how to cap the physical power limit of the GPU via `nvidia-smi -pl 220` at the OS level, modern enterprise requirements (such as EU ESG reporting mandates) demand granular accounting.

If a multi-tenant node consumes 300 Watts total, administrators must know exactly how many Watts were burned by Team A's `embedding-service` vs. Team B's `vllm-service`. DCGM alone provides aggregate GPU power, but attributing it accurately to Time-Sliced pods requires deeper kernel integration.

---

## 2. Kepler Architecture

**Kepler (Kubernetes-based Efficient Power Level Exporter)** utilizes eBPF (Extended Berkeley Packet Filter) to trace CPU performance counters, GPU utilization, and memory bandwidth directly in the Linux kernel without modifying the application code.

It then uses pre-trained Machine Learning models (running within Kepler itself) to infer the exact power consumption of each cgroup (Kubernetes Pod) based on its hardware utilization ratio.

---

## 3. Deployment

Kepler is deployed as a DaemonSet to ensure tracing occurs on all bare-metal nodes.

```bash
kubectl apply -f https://raw.githubusercontent.com/sustainable-computing-io/kepler/main/manifests/kubernetes/deployment.yaml
```

Ensure the DaemonSet is granted privileged access to load the eBPF kernel modules:
- `/sys/fs/cgroup` mounting
- `CAP_SYS_ADMIN` and `CAP_BPF`

---

## 4. Metric Telemetry

Kepler exposes granular Prometheus metrics that can be queried for ESG reporting or internal GreenOps dashboards.

### Query Examples

**1. Total Energy Consumed by a Specific Microservice (Joules):**
```promql
sum by (pod_name) (
  rate(kepler_container_joules_total{namespace="ml-workloads", pod_name=~"embedding-service.*"}[1h])
)
```

**2. GPU-Specific Power Draw per Namespace (Watts):**
```promql
sum by (namespace) (
  kepler_container_gpu_joules_total
)
```

### Integration with Kubecost

These metrics can be piped directly into Kubecost (`38-finops-kubecost-chargeback.md`), allowing the billing engine to charge teams not just for hardware amortization, but for the exact electricity cost (e.g., $0.15 per kWh) burned by their specific AI inferences.

---

**End of Architecture Documentation Series.**
