# Serverless GPU Scaling (Knative)

**Component:** Autoscaling & Serverless HTTP  
**Objective:** Scale synchronous endpoints to zero to reclaim idle VRAM  
**Architecture:** Knative Serving  

---

## 1. The Idle VRAM Waste

KEDA (`20-keda-autoscaling.md`) perfectly autoscales background Celery workers based on Redis queue length. 

However, synchronous HTTP APIs (like a FastAPI endpoint serving an internal corporate chatbot) cannot utilize queue-based scaling. If the chatbot receives zero traffic at 3:00 AM, the Kubernetes Deployment remains at `replicas: 1` to ensure the HTTP port remains open. This single pod continuously holds its 3.2GB GPU Time-Slice reservation, preventing background Ray training jobs from utilizing that idle VRAM.

---

## 2. Knative Serving Architecture

**Knative** introduces a true Serverless paradigm to Kubernetes. It intercepts HTTP traffic at the Ingress level.

1. **Scale-to-Zero:** If a Knative Service receives no HTTP requests for 60 seconds, it terminates all Pods (`replicas: 0`). The GPU VRAM is completely freed.
2. **Cold Start (Request Buffering):** When a user finally sends a request at 3:15 AM, the Knative Activator intercepts the HTTP payload, holds the connection open, rapidly spins up the Pod, and forwards the request once the FastAPI server is ready.
3. **Concurrency-Based Scaling:** Unlike standard HPA (which scales on CPU %), Knative scales based on concurrent in-flight HTTP requests.

---

## 3. Implementation

### 3.1 Install Knative

Deploy Knative Serving along with the Kourier or Istio networking layer.

```bash
# Install Knative Serving CRDs and Core
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.12.0/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.12.0/serving-core.yaml

# Install Istio integration (since Istio is our mesh)
kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.12.0/net-istio.yaml
```

### 3.2 Deploying a Serverless ML Endpoint

Instead of a standard Kubernetes `Deployment` and `Service`, define a Knative `Service` (ksvc).

```yaml
# vllm-serverless.yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: vllm-inference
  namespace: ml-workloads
spec:
  template:
    metadata:
      annotations:
        # Scale to zero enabled by default. Max replicas bounded.
        autoscaling.knative.dev/max-scale: "4"
        # Scale up if concurrent requests per pod exceeds 10
        autoscaling.knative.dev/target: "10"
    spec:
      containers:
      - image: vllm-openai:latest
        resources:
          limits:
            nvidia.com/gpu: 1
```

---

## 4. The Cold Start Trade-off

**Warning:** Scaling to zero introduces the "Cold Start" penalty.
When the first request arrives, the Pod must spin up, load Python, and load the 15GB model from NVMe into VRAM. Even with GPUDirect Storage (`49-gpu-direct-storage.md`), this may take 5–15 seconds. The HTTP client must be configured with a sufficiently long timeout.

**Optimization:** For critical user-facing APIs, utilize Knative's `min-scale: "1"` annotation to prevent zero-scaling, while applying `min-scale: "0"` strictly to internal/dev services.

---

## Next Steps

Proceed to `56-jupyterhub-ml-workspaces.md` to provision interactive cloud workspaces for Data Scientists.
