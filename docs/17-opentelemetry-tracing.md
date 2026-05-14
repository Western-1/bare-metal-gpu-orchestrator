# OpenTelemetry Tracing (Jaeger)

**Component:** OpenTelemetry (OTel) & Jaeger  
**Objective:** Distributed request tracing and inference latency profiling  
**Architecture:** OTLP gRPC via Auto-Instrumentation  

---

## 1. Tracing Architecture

Scaling GPU inference across distinct microservices (`vision`, `embedding`, `background-worker`) introduces observability fragmentation. Standard stdout logging is insufficient for tracking multi-hop request lifecycles.

The repository deploys **OpenTelemetry (OTel)** coupled with **Jaeger** to establish a distributed tracing backend capable of isolating discrete bottlenecks (e.g., FastAPI routing overhead vs. PyTorch CUDA execution).

---

## 2. Jaeger Deployment

For standard telemetry ingestion, the Jaeger `all-in-one` image provisions the Collector, in-memory Storage, and the UI in a unified container.

```yaml
# k8s/17-opentelemetry-tracing.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
  namespace: workloads
spec:
  containers:
  - name: jaeger
    image: jaegertracing/all-in-one:latest
    ports:
    - containerPort: 16686 # Jaeger Dashboard UI
    - containerPort: 4317  # OTLP gRPC (OpenTelemetry Protocol Ingestion)
```

---

## 3. Instrumentation Telemetry

Manual instrumentation of inference endpoints is avoided. The architecture leverages OpenTelemetry auto-instrumentation binaries.

**Execution Flow (e.g., `embedding-service`):**
1. **Ingress:** FastAPI middleware dynamically intercepts the request and generates a Root Trace Span.
2. **Compute:** As the payload enters the PyTorch execution context (`model.encode`), OTel hooks generate execution sub-spans.
3. **Egress:** The OTel exporter flushes the aggregate trace payload asynchronously via gRPC to `jaeger:4317`.

---

## 4. Telemetry Analysis

To visualize latency waterfalls and isolate API overhead from raw GPU execution time:

```bash
# Expose Jaeger UI locally
kubectl port-forward svc/jaeger 16686:16686 -n workloads
```

Navigate to `http://localhost:16686`. Query by service (`embedding-service`) to inspect discrete span durations.

---

## Next Steps

Proceed to `18-mlflow-registry.md` to configure artifact versioning and model deployment lifecycles.
