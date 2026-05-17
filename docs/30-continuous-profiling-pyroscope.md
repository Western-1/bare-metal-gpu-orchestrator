# Continuous Profiling (Grafana Pyroscope)

**Component:** Application Observability  
**Objective:** Identify Python GIL bottlenecks and asyncio lock contention  
**Architecture:** Grafana Pyroscope + eBPF / Python Tracing  

---

## 1. The Asynchronous Inference Problem

While the GPU performs matrix multiplication, the surrounding microservice (FastAPI + Uvicorn) acts as the data ingress/egress conduit. 

In high-throughput environments, the API wrapper often becomes the primary bottleneck before the GPU reaches saturation. Common issues include:
- **Global Interpreter Lock (GIL) Contention:** Heavy JSON serialization or synchronous array manipulation blocking the main event loop.
- **Asyncio Deadlocks:** Blocking I/O calls inadvertently executed within an asynchronous context.
- **Memory Leaks:** Unreleased object references expanding the application heap.

---

## 2. Pyroscope Architecture

To isolate execution bottlenecks, we deploy **Grafana Pyroscope**, a continuous profiling platform. Pyroscope samples stack traces thousands of times per second with minimal (<2%) overhead.

By analyzing Flamegraphs, engineers visually identify precisely which Python functions are consuming the most CPU cycles over specific time intervals.

---

## 3. Pyroscope Backend Deployment

Deploy the Pyroscope indexing server alongside the existing Prometheus/Loki stack.

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install pyroscope grafana/pyroscope \
  --namespace monitoring \
  --set "pyroscope.storage.type=filesystem" \
  --version 1.5.0
```

---

## 4. Application Instrumentation

Pyroscope provides a native Python agent to instrument FastAPI applications.

### Dependency Injection

Add `pyroscope-io` to `requirements.txt`.

### Code Implementation

Initialize the profiler immediately upon application startup (`main.py`), configuring it to target the Kubernetes telemetry backend.

```python
import pyroscope
import os

# Initialize Continuous Profiling
pyroscope.configure(
    application_name="embedding-service",
    # Point to the Kubernetes Service DNS
    server_address="http://pyroscope.monitoring.svc.cluster.local:4040", 
    tags={
        "region": "eu-central",
        "env": "production"
    },
    profile_cpu=True,
    profile_allocobjects=True,
    profile_inuseobjects=True,
)

from fastapi import FastAPI
app = FastAPI()
```

---

## 5. Flamegraph Analysis

1. Port-forward the Grafana dashboard (`kubectl port-forward svc/grafana 3000:80 -n monitoring`).
2. Add Pyroscope as a Data Source via the URL `http://pyroscope.monitoring.svc.cluster.local:4040`.
3. Open the **Explore** tab and select the Pyroscope source.

### Interpretation Metrics

- **X-Axis:** Represents the population of samples. The wider the bar, the more CPU time the function consumed.
- **Y-Axis:** Represents the call stack depth.
- **Actionable Insight:** If a function like `json.dumps()` or `numpy.array()` occupies 60% of the horizontal axis during a load test, refactor it to utilize a highly optimized library (e.g., `orjson`) or offload it to a ThreadPool.

---

## Next Steps

Proceed to `31-mig-vs-time-slicing.md` for a deeper architectural comparison of hardware vs software GPU multiplexing.
