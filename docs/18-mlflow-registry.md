# MLflow Model Registry

**Component:** MLflow Tracking Server  
**Objective:** Centralized artifact lifecycle management and version control  
**Integration:** FastAPI backend dynamic model loading  

---

## 1. MLOps Lifecycle Management

Manual artifact management (e.g., ad-hoc S3 synchronizations, `.pt` binary renaming) induces high deployment risk and limits audibility. 
To standardize deployment pipelines, this architecture utilizes **MLflow** as the authoritative source of truth for model versioning and production promotion.

---

## 2. MLflow Deployment

Deploy the MLflow tracking server to the cluster. 

*Note: The included manifest provisions a SQLite backend for local validation. Production environments must inject PostgreSQL and S3 credentials via `backend-store-uri` and `default-artifact-root`.*

```yaml
# k8s/18-mlflow-registry.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow
  namespace: workloads
spec:
  containers:
  - name: mlflow
    image: ghcr.io/mlflow/mlflow:latest
    command: 
    - "mlflow"
    - "server"
    - "--host"
    - "0.0.0.0"
    - "--backend-store-uri"
    - "sqlite:///mlflow.db"
    ports:
    - containerPort: 5000
```

---

## 3. Workload Integration

### Upstream (Training Pipeline)

Model training pipelines push serialized artifacts and telemetry directly to the tracking server:

```python
import mlflow

# Log serialized model and register version
mlflow.pytorch.log_model(
    pytorch_model, 
    "resnet18", 
    registered_model_name="vision-classifier"
)
```

### Downstream (Inference Microservices)

Inference services (`vision-service`, `embedding-service`) are decoupled from hardcoded paths. Upon Pod initialization, the services query the MLflow API for the artifact tagged as `Production` and pull the binaries into the PVC cache prior to executing the inference engine.

---

## 4. UI Access

To visualize artifact lineage or manually promote staging versions to production:

```bash
kubectl port-forward svc/mlflow 5000:5000 -n workloads
```
Access the dashboard at `http://localhost:5000`.

---

## Next Steps

Proceed to `19-concurrency-limits.md` to establish internal API throttling limits.
