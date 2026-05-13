# 17. OpenTelemetry Tracing (Jaeger)

As our GPU infrastructure scales to handle thousands of requests across multiple services (`vision`, `embedding`, `background-worker`), tracking a single user's request through the entire system becomes impossible with standard logs.

To solve this, we deploy **OpenTelemetry** with **Jaeger** as our distributed tracing backend.

---

## 1. The Jaeger Architecture

We deploy the Jaeger "all-in-one" image which includes the Collector, Storage (in-memory for local dev), and the UI.

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
    - containerPort: 16686 # UI
    - containerPort: 4317  # OTLP gRPC (OpenTelemetry Protocol)
```

## 2. How Services Report Traces

Instead of instrumenting our Python code manually, we use the OpenTelemetry auto-instrumentation libraries for FastAPI and PyTorch.

When a request arrives at the `embedding-service`:
1. FastAPI automatically creates a "Trace Span".
2. When the request enters PyTorch (`model.encode`), a sub-span is created.
3. The OpenTelemetry exporter sends this trace data asynchronously via gRPC to `jaeger:4317`.

## 3. Viewing Traces

Once deployed (via `make deploy-advanced`), you can access the Jaeger UI to visualize request flows:

1. **Port Forward the UI**:
   ```bash
   kubectl port-forward svc/jaeger 16686:16686 -n workloads
   ```
2. **Access the Dashboard**: Open `http://localhost:16686` in your browser.
3. **Analyze Bottlenecks**: You will see exactly how many milliseconds were spent inside FastAPI routing vs. actual PyTorch GPU inference.
