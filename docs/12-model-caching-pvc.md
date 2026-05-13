# 12. Model Caching and Shared Volumes

In a Time-Sliced architecture, you may have 4 or more pod replicas of the same service (e.g., an embedding API) running concurrently on the same physical node.

If each pod downloads its multi-GB Hugging Face model on startup, you will experience:
- Severe cold-start latency (taking minutes to become ready).
- Wasted network bandwidth.
- Unnecessary disk space consumption (4 replicas downloading a 5GB model consumes 20GB of local storage).

To solve this, we use a shared `HostPath` Persistent Volume (PV) to mount a local SSD directory directly into the pods. The model is downloaded once and instantly shared across all replicas.

---

## 1. Create the Host Directory

First, create a directory on the bare-metal host's fast NVMe SSD where models will be cached. Ensure the permissions allow pods to read/write.

```bash
# Run on the bare-metal host
sudo mkdir -p /mnt/nvme/huggingface-cache
sudo chown -R 1000:1000 /mnt/nvme/huggingface-cache
sudo chmod -R 775 /mnt/nvme/huggingface-cache
```

---

## 2. Define the Persistent Volume (PV) and Claim (PVC)

Create a Kubernetes `PersistentVolume` mapping to the host path, and a `PersistentVolumeClaim` that our workloads can bind to. Since we want all pods to read/write from this cache, we use `ReadWriteMany`.

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

Apply the storage resources:
```bash
kubectl apply -f manifests/storage/hf-cache-pv-pvc.yaml
```

---

## 3. Mount the Cache into the Workload

Modify your FastAPI deployments to mount this PVC into the container's Hugging Face cache directory (`/root/.cache/huggingface` by default, or overridden by `HF_HOME`).

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
        # Explicitly define the Hugging Face cache directory
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

### How It Works in Practice

1. **Pod 1 starts:** Checks `/app/models-cache`. The model isn't there, so it downloads it from Hugging Face into the mounted HostPath volume.
2. **Pods 2, 3, and 4 start (concurrently or later):** They check `/app/models-cache`. The model is already present. They instantly load the model into VRAM (or their memory fraction).
3. **Result:** Cold start goes from minutes to seconds, and 15GB of disk space is saved.

### Warning on Concurrent Downloads

If all 4 pods start at the exact same millisecond on a completely empty cache, they may all try to download the file simultaneously, causing write collisions. 
To mitigate this, you can:
- Use an `initContainer` in one specific pod.
- **Pre-download the model directly onto the host path using our setup script.**
- Rely on Hugging Face's built-in file locking mechanism (supported in `huggingface_hub >= 0.14`).

---

## 4. Local Development (Docker Compose)

For local testing via `make run-local`, we map a local directory (`.cache/models`) directly into the containers.
To prevent concurrent download issues locally, you should pre-download the models using the provided script before starting the workloads:

```bash
# Run this once on your local machine
./scripts/download-models.sh
```

This script securely downloads the `all-MiniLM-L6-v2` and `resnet18` models into `.cache/models`, which is then mounted via `docker-compose.yaml` to all replicas instantly.
