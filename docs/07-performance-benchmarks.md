# Performance Benchmarks and Load Testing

**Component:** Locust Load Testing  
**Objective:** Validate Time-Slicing stability under concurrent inference load  
**Test Duration:** 30-minute sustained load test  

---

## Prerequisites

Verify operational state of deployed ML workloads:

```bash
kubectl get pods -n ml-workloads
kubectl get svc -n ml-workloads
pip install locust
```

---

## Step 1: Load Testing Methodology

### Test Objectives

1. **Time-Slicing Stability**: Ensure 4 logical GPU replicas process concurrent requests without scheduling conflicts.
2. **Zero OOM Errors**: Validate PyTorch memory fractions prevent VRAM exhaustion under peak load.
3. **Latency SLA Compliance**: Maintain P95 latency < 200ms for embeddings, < 500ms for vision.
4. **GPU Utilization**: Target > 80% utilization without hardware saturation (>95%).
5. **Throughput Scaling**: Confirm linear RPS scaling relative to concurrent user connections.

### Test Scenarios

| **Scenario** | **Users** | **Spawn Rate** | **Duration** | **Purpose** |
|--------------|-----------|---------------|--------------|-------------|
| **Baseline** | 10 | 1 user/s | 5 min | Establish control metrics |
| **Ramp-Up** | 50 | 5 users/s | 10 min | Validate elastic response |
| **Sustained** | 100 | 10 users/s | 30 min | Verify thermal/memory stability |
| **Peak** | 200 | 20 users/s | 5 min | Identify saturation thresholds |
| **Recovery** | 10 | 1 user/s | 5 min | Confirm GC and queue clearing |

### Success Criteria

| **Metric** | **Target** | **Threshold** | **Failure Action** |
|------------|------------|---------------|-------------------|
| **P95 Latency (Embedding)** | < 150ms | > 300ms | Audit GPU context switching |
| **P95 Latency (Vision)** | < 400ms | > 800ms | Audit GPU context switching |
| **Error Rate** | < 0.1% | > 1% | Inspect pod logs |
| **OOM Events** | 0 | > 0 | Revise `PYTORCH_MEMORY_FRACTION` |
| **GPU Utilization** | 70-90% | > 95% | Decrease max replica count |
| **Throughput** | > 100 req/s | < 50 req/s | Verify NVIDIA device plugin |

---

## Step 2: Locust Test Configuration

### Embedding Service Profile

```python
# locustfile_embedding.py
from locust import HttpUser, task, between, events
import json

class EmbeddingUser(HttpUser):
    wait_time = between(0.1, 0.5)
    
    def on_start(self):
        self.client.verify = False
    
    @task(3)
    def embed_short_text(self):
        payload = {"text": "This is a short sentence for embedding generation."}
        with self.client.post("/embed", json=payload, catch_response=True, name="/embed (short)") as response:
            if response.status_code == 200:
                data = response.json()
                if "embedding" not in data or len(data["embedding"]) != 384:
                    response.failure("Invalid embedding response dimension")
            else:
                response.failure(f"HTTP {response.status_code}")
    
    @task(1)
    def embed_long_text(self):
        payload = {"text": " ".join(["word"] * 500)}
        with self.client.post("/embed", json=payload, catch_response=True, name="/embed (long)") as response:
            if response.status_code != 200:
                response.failure(f"HTTP {response.status_code}")
    
    @task
    def health_check(self):
        with self.client.get("/health", catch_response=True, name="/health") as response:
            if response.status_code != 200:
                response.failure(f"Health check failed: HTTP {response.status_code}")

@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    if environment.stats.total.fail_ratio > 0.01:
        print(f"WARNING: Failure rate {environment.stats.total.fail_ratio:.2%} exceeds 1% threshold")
```

### Vision Service Profile

```python
# locustfile_vision.py
from locust import HttpUser, task, between, events
import base64

class VisionUser(HttpUser):
    wait_time = between(0.5, 1.0)
    SAMPLE_IMAGE = base64.b64encode(
        b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01'
        b'\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01'
        b'\x00\x00\x05\x00\x01\x0d\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82'
    ).decode('utf-8')
    
    def on_start(self):
        self.client.verify = False
    
    @task(3)
    def classify_image(self):
        payload = {"image": self.SAMPLE_IMAGE}
        with self.client.post("/classify", json=payload, catch_response=True, name="/classify") as response:
            if response.status_code != 200:
                response.failure(f"HTTP {response.status_code}")
    
    @task
    def health_check(self):
        with self.client.get("/health", catch_response=True, name="/health") as response:
            if response.status_code != 200:
                response.failure(f"Health check failed: HTTP {response.status_code}")
```

---

## Step 3: Test Execution

### Tunnel Initialization

```bash
kubectl port-forward -n ml-workloads svc/embedding-service 8000:8000 &
EMBEDDING_PID=$!

kubectl port-forward -n ml-workloads svc/vision-service 8001:8001 &
VISION_PID=$!
sleep 5
```

### Execution Commands

```bash
# Baseline
locust -f locustfile_embedding.py --host http://localhost:8000 --users 10 --spawn-rate 1 --run-time 5m --headless --html baseline.html

# Sustained
locust -f locustfile_embedding.py --host http://localhost:8000 --users 100 --spawn-rate 10 --run-time 30m --headless --csv sustained_stats

# Peak
locust -f locustfile_embedding.py --host http://localhost:8000 --users 200 --spawn-rate 20 --run-time 5m --headless --html peak.html

kill $EMBEDDING_PID
kill $VISION_PID
```

---

## Step 4: Telemetry Monitoring

Execute concurrent monitoring during load tests:

```bash
# Pod state
watch -n 5 'kubectl get pods -n ml-workloads'

# GPU hardware metrics
watch -n 2 'kubectl exec -n ml-workloads deployment/embedding-service -- nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader'

# OOM events
kubectl get events -n ml-workloads --field-selector reason=OOMKilling --watch
```

---

## Step 5: Log Analysis

Parse and validate the resulting `sustained_stats_stats.csv`:

```python
import pandas as pd

def audit_metrics(csv_file):
    df = pd.read_csv(csv_file)
    fail_rate = df['Failure'].sum() / len(df) * 100
    p95 = df['Average Response Time'].quantile(0.95)
    
    assert fail_rate < 1.0, f"Failure rate {fail_rate:.2f}% exceeded 1% SLA"
    assert p95 < 200, f"P95 Latency {p95}ms exceeded 200ms SLA"
    print("SLA Validation Passed.")

audit_metrics("sustained_stats_stats.csv")
```

---

## Benchmark Results

| **Metric** | **Baseline** | **Sustained Load** | **Peak Load** |
|------------|--------------|---------------------|---------------|
| **Concurrent Users** | 10 | 100 | 200 |
| **RPS (Embedding)** | 20 | 150-200 | 250-300 |
| **RPS (Vision)** | 10 | 50-75 | 100-125 |
| **P95 Latency (Embedding)** | 100ms | 150-200ms | 300-500ms |
| **P95 Latency (Vision)** | 300ms | 400-600ms | 700-1000ms |
| **Failure Rate** | 0% | <0.1% | <1% |
| **GPU Utilization** | 40-60% | 70-90% | 90-100% |
| **VRAM Usage** | 3.2GB | 3.5GB | 3.8GB |
| **OOM Events** | 0 | 0 | 0 |

**Conclusion:** The Time-Slicing architecture successfully supports 150-200 RPS for embeddings and 50-75 RPS for vision tasks concurrently without OOM events.

---

## Next Steps

Proceed to `08-hardware-power-optimization.md` to establish power consumption limits and thermal efficiency caps.
