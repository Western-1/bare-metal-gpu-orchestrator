# Concurrency Limits (OOM Protection)

**Component:** Application-Layer Concurrency Control  
**Objective:** Prevent PyTorch CUDA OOM errors under synchronous load  
**Mechanism:** `asyncio.Semaphore`  

---

## 1. Synchronous Inference Bottleneck

Executing PyTorch models within a strictly partitioned VRAM context (e.g., a 3.2 GB Time-Sliced boundary) dictates a hard ceiling on concurrent inference execution. Exposing the API to unthrottled HTTP traffic guarantees a rapid Out Of Memory (OOM) fault during ingress spikes.

While message brokers (e.g., Redis/Celery) mitigate this for asynchronous background jobs, they introduce unacceptable queuing latency for synchronous REST APIs requiring sub-second SLAs.

---

## 2. Semaphore Implementation Strategy

To protect the CUDA execution graph without sacrificing synchronous latency, we implement application-layer concurrency control using `asyncio.Semaphore`.

**Execution Flow:**
1. **Initialization:** The semaphore instantiates with a strict concurrency ceiling (e.g., `4`).
2. **Ingress:** If 50 concurrent requests hit the FastAPI router, 4 acquire the lock and dispatch to the GPU.
3. **RAM Queuing:** The remaining 46 requests yield at the `async with semaphore:` block, queuing safely in abundant system RAM without allocating VRAM tensors.
4. **Release:** Upon completion of a GPU forward pass, the lock is released, immediately admitting the next queued request in a FIFO pattern.

---

## 3. Configuration Management

Concurrency ceilings are exposed dynamically via the `MAX_CONCURRENT_REQUESTS` environment variable to allow runtime tuning.

### Container Environment Mapping

Inject the variable into the deployment spec:

```yaml
# manifests/workloads/embedding-api.yaml
        env:
        - name: MAX_CONCURRENT_REQUESTS
          value: "16" # Must be calibrated via load testing
```

---

## 4. Calibration Methodology

The maximum safe concurrency is a function of static model weights, dynamic KV cache growth, and the hard VRAM partition limit. 

**Tuning Protocol:**
1. Execute a sustained Locust load test (reference `07-performance-benchmarks.md`).
2. Monitor VRAM telemetry via DCGM exporter or the internal `/health` endpoint (`memory_stats`).
3. Iteratively increment `MAX_CONCURRENT_REQUESTS` until peak VRAM utilization stabilizes at ~85-90% under sustained load. Exceeding 90% introduces severe risk of fragmentation-induced OOMs.

---

## Next Steps

Proceed to `20-keda-autoscaling.md` to configure Kubernetes Event-Driven Autoscaling based on Redis queue depths.
