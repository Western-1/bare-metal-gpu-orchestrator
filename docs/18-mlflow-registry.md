# 18. MLflow Model Registry

Managing machine learning model versions manually (e.g., uploading files to S3 buckets, renaming `.pt` files, updating environment variables) is error-prone and doesn't scale.

To automate model versioning and artifact management across our Kubernetes cluster, we use **MLflow**.

---

## 1. The MLflow Deployment

We deploy the official MLflow tracking server within our cluster. For simplicity in our current configuration, it uses a local SQLite backend, but in production, this connects to a PostgreSQL database and an S3 bucket for artifact storage.

```yaml
# k8s/18-mlflow-registry.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow
spec:
  containers:
  - name: mlflow
    image: ghcr.io/mlflow/mlflow:latest
    command: ["mlflow", "server", "--host", "0.0.0.0", "--backend-store-uri", "sqlite:///mlflow.db"]
    ports:
    - containerPort: 5000
```

## 2. Integration with Workloads

When our data scientists train a new version of the Vision or Embedding models, they use the MLflow Python API to register the model:

```python
import mlflow
mlflow.pytorch.log_model(pytorch_model, "resnet18", registered_model_name="vision-classifier")
```

Our FastAPI microservices (`vision-service`, `embedding-service`) are configured to dynamically pull the latest "Production" tagged model from the MLflow registry at startup, rather than hardcoding a specific HuggingFace path.

## 3. Accessing the MLflow UI

You can view the Model Registry, compare training runs, and promote models to production via the MLflow web interface:

1. **Port Forward the UI**:
   ```bash
   kubectl port-forward svc/mlflow 5000:5000 -n workloads
   ```
2. **Access the Dashboard**: Open `http://localhost:5000` in your browser.
