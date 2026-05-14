# Model Caching and Shared Volumes

**Component:** PersistentVolumeClaims (PVC) and HostPath Storage  
**Objective:** Eliminate redundant multi-gigabyte model downloads and prevent OOM spikes  
**Storage Class:** local-path  

---

## 1. Storage Architecture Overview

In a Time-Sliced architecture with multiple concurrent replicas (e.g., 4 pods of an embedding API), initializing containers simultaneously triggers redundant downloads of identical model weights (e.g., Hugging Face `.safetensors`).

**Impact of Redundant Downloads:**
- Network bandwidth saturation.
- Severe cold-start latency (pulling 5GB+ per pod).
- Wasted disk utilization (4 replicas × 5GB = 20GB local storage).

**Solution:** Implement a shared `HostPath` Persistent Volume (PV). A single cache directory on the host's NVMe SSD is mounted across all replicas with `ReadWriteMany` (RWX) permissions.

---

## 2. Host Storage Configuration

Provision the physical directory on the bare-metal host:

```bash
# Execute on the k3s node
sudo mkdir -p /mnt/nvme/huggingface-cache
sudo chown -R 1000:1000 /mnt/nvme/huggingface-cache
sudo chmod -R 775 /mnt/nvme/huggingface-cache
```

---

## 3. Kubernetes Storage Manifests

Define the `PersistentVolume` and `PersistentVolumeClaim` to abstract the host path:

```yaml
# manifests/storage/hf-cache-pv-pvc.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: hf-cache-pv
  labels:
    type: local
spec:
  storageClassName: local-path
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteMany
  hostPath:
    path: "/mnt/nvme/huggingface-cache"
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hf-cache-pvc
  namespace: ml-workloads
spec:
  storageClassName: local-path
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 50Gi
```

```bash
kubectl apply -f manifests/storage/hf-cache-pv-pvc.yaml
```

---

## 4. Workload Mount Configuration

Inject the PVC into workload manifests and override the default Hugging Face cache directory via `HF_HOME`.

```yaml
# manifests/workloads/embedding-api.yaml (Excerpt)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: embedding-service
  namespace: ml-workloads
spec:
  replicas: 4
  template:
    spec:
      containers:
      - name: api
        image: my-registry/embedding-api:v1.0
        env:
        - name: HF_HOME
          value: "/app/models-cache"
        volumeMounts:
        - name: hf-cache-volume
          mountPath: "/app/models-cache"
      volumes:
      - name: hf-cache-volume
        persistentVolumeClaim:
          claimName: hf-cache-pvc
```

### Concurrency and Lock Management

When multiple pods initiate simultaneously on a cold cache, write collisions may occur.
`huggingface_hub >= 0.14` supports native file locking. To guarantee collision avoidance, execute an out-of-band pre-fetch:

```bash
# Pre-warm the cache directory on the host prior to deployment
HF_HOME=/mnt/nvme/huggingface-cache huggingface-cli download sentence-transformers/all-MiniLM-L6-v2
```

---

## 5. Local Development (Docker Compose)

For local environments utilizing `make run-local`, map `.cache/models` directly to the containers. 
Execute the pre-download script to populate the local cache prior to container initialization:

```bash
./scripts/download-models.sh
```

---

## Next Steps

Proceed to `13-api-gateway-rate-limiting.md` to configure ingress load balancing and strict rate-limiting topologies.
