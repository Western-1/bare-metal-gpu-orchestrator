# Workloads and Memory Management

**Component:** FastAPI + PyTorch Services with GPU Allocation  
**Objective:** Deploy ML inference workloads without OOM kills  
**Namespace:** ml-workloads  

---

## Prerequisites

Ensure GPU Time-Slicing is configured from `02-gpu-time-slicing-config.md`:

```bash
# Verify GPU replicas are available
kubectl describe node gpu-node-1 | grep "nvidia.com/gpu"
# Expected: nvidia.com/gpu: 4

# Verify namespace exists
kubectl get namespaces | grep ml-workloads
```

---

## Step 1: Memory Strategy Overview

### VRAM Allocation Budget

With 16GB VRAM and 4 replicas, the memory budget is:

| **Workload** | **Target VRAM** | **PyTorch Fraction** | **System RAM** | **Purpose** |
|--------------|-----------------|---------------------|----------------|-------------|
| Embedding API | 3GB | 0.20 (20%) | 2Gi request, 4Gi limit | Text embedding inference |
| Vision API | 3GB | 0.20 (20%) | 2Gi request, 4Gi limit | Image classification |
| Background Worker | 3GB | 0.20 (20%) | 2Gi request, 4Gi limit | Async ML tasks |
| **Total Allocated** | **9GB** | **60%** | **6Gi** | **Workloads** |
| **Headroom** | **7GB** | **40%** | **26Gi** | **Fragmentation + Driver** |

### Memory Isolation Layers

1. **Kubernetes System RAM Limits:** Prevents pods from consuming all host memory
2. **PyTorch VRAM Fractioning:** Limits PyTorch to specific VRAM percentage
3. **FastAPI Request Limits:** Prevents large payloads from exhausting memory
4. **Model Pre-loading:** Allocates VRAM on startup to avoid runtime spikes

---

## Step 2: PyTorch Memory Management Code

### Memory Configuration Module

Create a reusable PyTorch memory configuration module:

```python
# gpu_memory_config.py
import torch
import os

def configure_gpu_memory(
    device_id: int = 0,
    memory_fraction: float = 0.20,
    enable_tf32: bool = True
) -> torch.device:
    """
    Configure PyTorch GPU memory settings for Time-Sliced environments.
    
    Args:
        device_id: GPU device ID (default: 0)
        memory_fraction: Fraction of total VRAM to allocate (default: 0.20 for 3GB on 16GB)
        enable_tf32: Enable TF32 tensor cores for faster computation
    
    Returns:
        Configured torch.device
    """
    # Verify CUDA availability
    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is not available. Check GPU driver and container runtime.")
    
    # Set device
    device = torch.device(f"cuda:{device_id}")
    torch.cuda.set_device(device)
    
    # Set memory fraction to limit VRAM usage
    torch.cuda.set_per_process_memory_fraction(
        fraction=memory_fraction,
        device=device_id
    )
    
    # Enable TF32 for faster computation (minimal precision loss for inference)
    if enable_tf32:
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True
    
    # Disable memory allocator stats to reduce overhead
    torch.cuda.memory._record_memory_history(False)
    
    # Print memory configuration
    total_vram = torch.cuda.get_device_properties(device_id).total_memory / (1024**3)
    allocated_vram = total_vram * memory_fraction
    print(f"GPU Memory Configuration:")
    print(f"  Device: CUDA:{device_id}")
    print(f"  Total VRAM: {total_vram:.2f} GB")
    print(f"  Allocated VRAM: {allocated_vram:.2f} GB ({memory_fraction*100:.0f}%)")
    print(f"  TF32 Enabled: {enable_tf32}")
    
    return device


def warmup_model(model: torch.nn.Module, device: torch.device, input_shape: tuple) -> None:
    """
    Perform a warmup forward pass to pre-allocate VRAM.
    
    Args:
        model: PyTorch model to warmup
        device: torch.device to run warmup on
        input_shape: Input tensor shape for warmup
    """
    model.eval()
    with torch.no_grad():
        dummy_input = torch.randn(*input_shape).to(device)
        _ = model(dummy_input)
    
    # Print memory usage after warmup
    allocated = torch.cuda.memory_allocated(device) / (1024**3)
    reserved = torch.cuda.memory_reserved(device) / (1024**3)
    print(f"Memory after warmup:")
    print(f"  Allocated: {allocated:.2f} GB")
    print(f"  Reserved: {reserved:.2f} GB")


def get_memory_stats(device: torch.device) -> dict:
    """
    Get current GPU memory statistics.
    
    Args:
        device: torch.device to query
    
    Returns:
        Dictionary with memory statistics
    """
    allocated = torch.cuda.memory_allocated(device) / (1024**3)
    reserved = torch.cuda.memory_reserved(device) / (1024**3)
    total = torch.cuda.get_device_properties(device).total_memory / (1024**3)
    
    return {
        "allocated_gb": allocated,
        "reserved_gb": reserved,
        "total_gb": total,
        "utilization_percent": (allocated / total) * 100
    }
```

### Usage Example in FastAPI Service

```python
# main.py (Embedding API)
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import torch
from sentence_transformers import SentenceTransformer
from gpu_memory_config import configure_gpu_memory, warmup_model, get_memory_stats

app = FastAPI(title="Embedding API")

# Configure GPU memory on startup
device = configure_gpu_memory(device_id=0, memory_fraction=0.20)

# Load model
model = SentenceTransformer('all-MiniLM-L6-v2')
model = model.to(device)

# Warmup model to pre-allocate VRAM
warmup_model(model, device, input_shape=(1, 512))

class EmbeddingRequest(BaseModel):
    text: str

@app.post("/embed")
async def embed(request: EmbeddingRequest):
    """Generate text embeddings."""
    try:
        # Get memory stats before inference
        stats_before = get_memory_stats(device)
        
        # Generate embedding
        with torch.no_grad():
            embedding = model.encode(request.text, convert_to_tensor=True)
        
        # Get memory stats after inference
        stats_after = get_memory_stats(device)
        
        # Return embedding as list
        return {
            "embedding": embedding.cpu().tolist(),
            "memory_stats": {
                "before": stats_before,
                "after": stats_after
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health():
    """Health check endpoint."""
    stats = get_memory_stats(device)
    return {
        "status": "healthy",
        "memory_stats": stats
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

### Usage Example for Vision API

```python
# main.py (Vision API)
from fastapi import FastAPI, File, UploadFile, HTTPException
from PIL import Image
import torch
import torchvision.transforms as transforms
from torchvision.models import resnet18, ResNet18_Weights
from gpu_memory_config import configure_gpu_memory, warmup_model, get_memory_stats

app = FastAPI(title="Vision API")

# Configure GPU memory
device = configure_gpu_memory(device_id=0, memory_fraction=0.20)

# Load pretrained ResNet-18
weights = ResNet18_Weights.DEFAULT
model = resnet18(weights=weights)
model = model.to(device)
model.eval()

# Image preprocessing
preprocess = weights.transforms()

# Warmup model
warmup_model(model, device, input_shape=(1, 3, 224, 224))

@app.post("/classify")
async def classify(file: UploadFile = File(...)):
    """Classify uploaded image."""
    try:
        # Read and preprocess image
        image = Image.open(file.file)
        image_tensor = preprocess(image).unsqueeze(0).to(device)
        
        # Get memory stats
        stats_before = get_memory_stats(device)
        
        # Inference
        with torch.no_grad():
            prediction = model(image_tensor)
        
        stats_after = get_memory_stats(device)
        
        # Get predicted class
        category_id = prediction.argmax().item()
        category_name = weights.meta["categories"][category_id]
        
        return {
            "category": category_name,
            "confidence": float(prediction.softmax(dim=1)[0][category_id]),
            "memory_stats": {
                "before": stats_before,
                "after": stats_after
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health():
    """Health check endpoint."""
    stats = get_memory_stats(device)
    return {
        "status": "healthy",
        "memory_stats": stats
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
```

---

## Step 3: Kubernetes Deployment Template

### Standard Deployment Template

Create a reusable Deployment template for GPU workloads:

```yaml
# gpu-workload-deployment-template.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <SERVICE_NAME>
  namespace: ml-workloads
  labels:
    app: <SERVICE_NAME>
    workload-type: gpu-inference
spec:
  replicas: 1
  selector:
    matchLabels:
      app: <SERVICE_NAME>
  template:
    metadata:
      labels:
        app: <SERVICE_NAME>
        workload-type: gpu-inference
    spec:
      containers:
      - name: <SERVICE_NAME>
        image: <IMAGE_REGISTRY>/<SERVICE_NAME>:<TAG>
        ports:
        - containerPort: <PORT>
          name: http
          protocol: TCP
        resources:
          requests:
            memory: "2Gi"
            nvidia.com/gpu: 1
          limits:
            memory: "4Gi"
            nvidia.com/gpu: 1
        env:
        - name: CUDA_VISIBLE_DEVICES
          value: "0"
        - name: PYTORCH_MEMORY_FRACTION
          value: "0.20"
        livenessProbe:
          httpGet:
            path: /health
            port: <PORT>
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: <PORT>
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
      nodeSelector:
        kubernetes.io/hostname: gpu-node-1
```

### Embedding Service Deployment

```yaml
# embedding-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: embedding-service
  namespace: ml-workloads
  labels:
    app: embedding-service
    workload-type: gpu-inference
spec:
  replicas: 1
  selector:
    matchLabels:
      app: embedding-service
  template:
    metadata:
      labels:
        app: embedding-service
        workload-type: gpu-inference
    spec:
      containers:
      - name: embedding-service
        image: your-registry/embedding-service:latest
        ports:
        - containerPort: 8000
          name: http
          protocol: TCP
        resources:
          requests:
            memory: "2Gi"
            nvidia.com/gpu: 1
          limits:
            memory: "4Gi"
            nvidia.com/gpu: 1
        env:
        - name: CUDA_VISIBLE_DEVICES
          value: "0"
        - name: PYTORCH_MEMORY_FRACTION
          value: "0.20"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
      nodeSelector:
        kubernetes.io/hostname: gpu-node-1
---
apiVersion: v1
kind: Service
metadata:
  name: embedding-service
  namespace: ml-workloads
spec:
  selector:
    app: embedding-service
  ports:
  - port: 8000
    targetPort: 8000
    name: http
  type: ClusterIP
```

### Vision Service Deployment

```yaml
# vision-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vision-service
  namespace: ml-workloads
  labels:
    app: vision-service
    workload-type: gpu-inference
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vision-service
  template:
    metadata:
      labels:
        app: vision-service
        workload-type: gpu-inference
    spec:
      containers:
      - name: vision-service
        image: your-registry/vision-service:latest
        ports:
        - containerPort: 8001
          name: http
          protocol: TCP
        resources:
          requests:
            memory: "2Gi"
            nvidia.com/gpu: 1
          limits:
            memory: "4Gi"
            nvidia.com/gpu: 1
        env:
        - name: CUDA_VISIBLE_DEVICES
          value: "0"
        - name: PYTORCH_MEMORY_FRACTION
          value: "0.20"
        livenessProbe:
          httpGet:
            path: /health
            port: 8001
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: 8001
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
      nodeSelector:
        kubernetes.io/hostname: gpu-node-1
---
apiVersion: v1
kind: Service
metadata:
  name: vision-service
  namespace: ml-workloads
spec:
  selector:
    app: vision-service
  ports:
  - port: 8001
    targetPort: 8001
    name: http
  type: ClusterIP
```

### Background Worker Deployment

```yaml
# background-worker-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: background-worker
  namespace: ml-workloads
  labels:
    app: background-worker
    workload-type: gpu-processing
spec:
  replicas: 1
  selector:
    matchLabels:
      app: background-worker
  template:
    metadata:
      labels:
        app: background-worker
        workload-type: gpu-processing
    spec:
      containers:
      - name: background-worker
        image: your-registry/background-worker:latest
        resources:
          requests:
            memory: "2Gi"
            nvidia.com/gpu: 1
          limits:
            memory: "4Gi"
            nvidia.com/gpu: 1
        env:
        - name: CUDA_VISIBLE_DEVICES
          value: "0"
        - name: PYTORCH_MEMORY_FRACTION
          value: "0.20"
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
      nodeSelector:
        kubernetes.io/hostname: gpu-node-1
```

---

## Step 4: Apply Deployments

### Deploy All Workloads

```bash
# Apply embedding service
kubectl apply -f embedding-service-deployment.yaml

# Apply vision service
kubectl apply -f vision-service-deployment.yaml

# Apply background worker
kubectl apply -f background-worker-deployment.yaml
```

### Verify Deployment Status

```bash
# Check all deployments
kubectl get deployments -n ml-workloads

# Expected output:
# NAME                READY   UP-TO-DATE   AVAILABLE   AGE
# background-worker   1/1     1            1           10s
# embedding-service   1/1     1            1           10s
# vision-service      1/1     1            1           10s

# Check pods
kubectl get pods -n ml-workloads

# Expected output:
# NAME                                 READY   STATUS    RESTARTS   AGE
# background-worker-xxxxxxxxxx-xxxxx   1/1     Running   0          15s
# embedding-service-xxxxxxxxxx-xxxxx   1/1     Running   0          15s
# vision-service-xxxxxxxxxx-xxxxx      1/1     Running   0          15s
```

### Verify GPU Allocation

```bash
# Check that each pod has GPU allocated
kubectl get pods -n ml-workloads -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].resources.limits}{"\n"}{end}'

# Expected output:
# background-worker-xxxxx    {"cpu":"","memory":"4Gi","nvidia.com/gpu":"1"}
# embedding-service-xxxxx    {"cpu":"","memory":"4Gi","nvidia.com/gpu":"1"}
# vision-service-xxxxx       {"cpu":"","memory":"4Gi","nvidia.com/gpu":"1"}
```

### Check Node GPU Usage

```bash
# Check node allocatable vs. used
kubectl describe node gpu-node-1 | grep -A 20 "Allocatable"

# Expected output should show:
# Allocatable:
#   nvidia.com/gpu:     4

# Check allocated resources
kubectl describe node gpu-node-1 | grep -A 20 "Allocated resources"

# Expected output should show:
# Allocated resources:
#   (Total limits may be over 100 percent, i.e., overcommitted.)
#   Resource           Requests     Limits
#   --------           --------     ------
#   cpu                0            0
#   memory             6Gi         12Gi
#   nvidia.com/gpu     3            3
```

---

## Step 5: Verify Memory Configuration

### Check Pod Logs for Memory Configuration

```bash
# Check embedding service logs for memory configuration
kubectl logs -n ml-workloads -l app=embedding-service --tail=20

# Expected output:
# GPU Memory Configuration:
#   Device: CUDA:0
#   Total VRAM: 16.00 GB
#   Allocated VRAM: 3.20 GB (20%)
#   TF32 Enabled: True
# Memory after warmup:
#   Allocated: 0.45 GB
#   Reserved: 3.20 GB
```

### Check Health Endpoints

```bash
# Port-forward to embedding service
kubectl port-forward -n ml-workloads deployment/embedding-service 8000:8000 &

# Check health endpoint
curl http://localhost:8000/health

# Expected output:
# {
#   "status": "healthy",
#   "memory_stats": {
#     "allocated_gb": 0.45,
#     "reserved_gb": 3.2,
#     "total_gb": 16.0,
#     "utilization_percent": 2.8
#   }
# }

# Kill port-forward
pkill -f "port-forward"
```

### Test Inference

```bash
# Port-forward to embedding service
kubectl port-forward -n ml-workloads deployment/embedding-service 8000:8000 &

# Test embedding endpoint
curl -X POST http://localhost:8000/embed \
  -H "Content-Type: application/json" \
  -d '{"text": "This is a test sentence for embedding generation."}'

# Expected output:
# {
#   "embedding": [0.123, -0.456, ...],
#   "memory_stats": {
#     "before": {"allocated_gb": 0.45, ...},
#     "after": {"allocated_gb": 0.47, ...}
#   }
# }

# Kill port-forward
pkill -f "port-forward"
```

---

## Step 6: Monitor for OOM Events

### Check for OOMKilled Events

```bash
# Check pod events for OOMKilled
kubectl get events -n ml-workloads --field-selector reason=OOMKilling

# If any pods are OOMKilled, investigate:
kubectl describe pod <pod-name> -n ml-workloads

# Look for:
# Last State:     Terminated
#   Reason:       OOMKilled
#   Exit Code:    137
```

### Check Memory Usage

```bash
# Check current memory usage of pods
kubectl top pods -n ml-workloads

# Expected output:
# NAME                                 CPU(cores)   MEMORY(bytes)
# background-worker-xxxxxxxxxx-xxxxx   100m        1.5Gi
# embedding-service-xxxxxxxxxx-xxxxx   150m        1.8Gi
# vision-service-xxxxxxxxxx-xxxxx      200m        2.0Gi
```

### Check GPU Memory Usage

```bash
# Execute nvidia-smi inside a pod to check GPU memory
kubectl exec -n ml-workloads deployment/embedding-service -- nvidia-smi

# Expected output should show:
# +-----------------------------------------------------------------------------+
# | Processes:                                                                  |
# |  GPU   GI   CI        PID   Type   Process name                  GPU Memory |
# |        ID   ID                                                   Usage      |
# |=============================================================================|
# |    0   N/A  N/A      1234      C   python                           3500MiB |
# +-----------------------------------------------------------------------------+
```

---

## Verification Checklist

### ✅ Deployment Verification

```bash
# 1. All deployments are running
kubectl get deployments -n ml-workloads
# Expected: 3 deployments, all READY 1/1

# 2. All pods are running
kubectl get pods -n ml-workloads
# Expected: 3 pods, all Running

# 3. Each pod has GPU allocated
kubectl get pods -n ml-workloads -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].resources.limits.nvidia.com/gpu}{"\n"}{end}'
# Expected: Each pod shows "1"
```

### ✅ Memory Configuration Verification

```bash
# 4. Pod logs show correct memory configuration
kubectl logs -n ml-workloads -l app=embedding-service | grep "GPU Memory Configuration"
# Expected: Shows 20% allocation (3.2GB)

# 5. Health endpoints return memory stats
kubectl port-forward -n ml-workloads deployment/embedding-service 8000:8000 &
curl http://localhost:8000/health
pkill -f "port-forward"
# Expected: Returns memory_stats with utilization_percent < 20%

# 6. No OOMKilled events
kubectl get events -n ml-workloads --field-selector reason=OOMKilling
# Expected: No events returned
```

### ✅ Functional Verification

```bash
# 7. Inference endpoints work
kubectl port-forward -n ml-workloads deployment/embedding-service 8000:8000 &
curl -X POST http://localhost:8000/embed -H "Content-Type: application/json" -d '{"text":"test"}'
pkill -f "port-forward"
# Expected: Returns embedding vector

# 8. GPU memory usage is within limits
kubectl exec -n ml-workloads deployment/embedding-service -- nvidia-smi --query-gpu=memory.used --format=csv,noheader
# Expected: < 3500MiB per pod
```

---

## Troubleshooting

### Issue: Pod stuck in ContainerCreating with Insufficient GPU

**Symptom:** Pod never starts, events show "Insufficient nvidia.com/gpu".

**Solution:**
```bash
# Check available GPU replicas
kubectl describe node gpu-node-1 | grep "nvidia.com/gpu"

# If shows 1 instead of 4, Time-Slicing is not configured
# Refer to 02-gpu-time-slicing-config.md

# If shows 4 but still insufficient, check existing allocations
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.containers[0].resources.limits.nvidia.com/gpu}{"\n"}{end}'
```

### Issue: Pod OOMKilled despite memory limits

**Symptom:** Pod is OOMKilled even with 4Gi limit.

**Solution:**
```bash
# Check pod events
kubectl describe pod <pod-name> -n ml-workloads

# If system RAM OOM, increase limits:
# Edit deployment and increase memory limit from 4Gi to 6Gi

# If VRAM OOM (CUDA out of memory), reduce PyTorch fraction:
# Edit deployment and set PYTORCH_MEMORY_FRACTION to 0.15 instead of 0.20
```

### Issue: PyTorch ignores memory fraction

**Symptom:** Pod allocates more VRAM than configured fraction.

**Solution:**
```bash
# Verify environment variable is set
kubectl exec -n ml-workloads deployment/embedding-service -- env | grep PYTORCH

# If not set, add to deployment:
# env:
# - name: PYTORCH_MEMORY_FRACTION
#   value: "0.20"

# Verify code calls set_per_process_memory_fraction
kubectl logs -n ml-workloads deployment/embedding-service | grep "set_per_process_memory_fraction"
```

### Issue: Model loading fails with CUDA error

**Symptom:** Pod crashes during model loading with CUDA error.

**Solution:**
```bash
# Check pod logs
kubectl logs -n ml-workloads deployment/embedding-service

# Common error: "CUDA out of memory"
# Solution: Reduce model size or increase memory fraction

# Common error: "CUDA not available"
# Solution: Verify GPU is accessible in pod
kubectl exec -n ml-workloads deployment/embedding-service -- nvidia-smi
```

---

## Advanced Configuration

### Adjusting Memory Fraction Per Workload

Different workloads may require different VRAM allocations:

```yaml
# For embedding service (smaller model)
env:
- name: PYTORCH_MEMORY_FRACTION
  value: "0.15"  # 2.4GB for smaller model

# For vision service (larger model)
env:
- name: PYTORCH_MEMORY_FRACTION
  value: "0.25"  # 4GB for larger model
```

### Horizontal Pod Autoscaling

For higher throughput, increase replicas:

```yaml
# embedding-service-deployment.yaml
spec:
  replicas: 2  # Run 2 instances for higher throughput
```

**Note:** With 4 GPU replicas, you can run up to 4 GPU pods total. Adjust replica counts accordingly.

### Resource Requests vs. Limits

For production, consider different request/limit values:

```yaml
resources:
  requests:
    memory: "3Gi"      # Higher request for QoS
    nvidia.com/gpu: 1
  limits:
    memory: "6Gi"      # Higher limit for headroom
    nvidia.com/gpu: 1
```

---

## Next Steps

With workloads deployed and memory configured, proceed to:

**Document 4:** `04-observability-dcgm.md`

This document covers:
- Deploying DCGM Exporter for GPU telemetry
- Setting up Prometheus and Grafana via Helm
- Configuring PromQL queries for per-pod GPU monitoring
