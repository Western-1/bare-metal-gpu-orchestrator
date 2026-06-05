# Feature Store Architecture (Feast)

**Component:** Feature Store  
**Objective:** Decouple feature engineering from inference pipelines  
**Architecture:** Feast + Redis (Online) + S3 (Offline)  

---

## 1. The Real-Time Inference Problem

Machine learning models require features (inputs) to make predictions. While some features are derived immediately from the HTTP request (e.g., the text of a search query), other critical features are historical and must be retrieved at inference time (e.g., the user's click-through rate over the last 30 days, or the average transaction size of a credit card).

Hardcoding database queries inside the FastAPI endpoints to calculate these metrics at runtime induces unacceptable latency (1000ms+) and heavily couples the ML engineering to the backend database schema.

---

## 2. Feast Feature Store

To achieve Sub-10ms inference latencies, we introduce **Feast (Feature Store)**.

Feast acts as the centralized bridge between Data Engineering and MLOps, maintaining two synchronization paths:
1. **Offline Store (MinIO / Parquet):** Used by Data Scientists to access massive historical datasets for training models without complex SQL joins.
2. **Online Store (Redis):** Extremely fast, low-latency key-value store used by the FastAPI inference engine to fetch the latest pre-computed feature values at runtime.

---

## 3. Deployment Configuration

### 3.1 Defining Features in Git

Feature definitions are stored as Python code in the repository and deployed via CI/CD.

```python
# features.py
from feast import Entity, FeatureView, Field, FileSource
from feast.types import Float32, Int64

# Define an entity (the Primary Key)
user = Entity(name="user_id", join_keys=["user_id"])

# Define the data source
user_stats_source = FileSource(
    path="s3://ml-data/user_stats.parquet",
    timestamp_field="event_timestamp",
)

# Define the Feature View
user_stats_view = FeatureView(
    name="user_stats",
    entities=[user],
    ttl=timedelta(days=1),
    schema=[
        Field(name="ctr_30_days", dtype=Float32),
        Field(name="purchase_count", dtype=Int64),
    ],
    source=user_stats_source,
)
```

### 3.2 Materialization

A Kubernetes CronJob executes the `feast materialize` command every 15 minutes, pushing the newly calculated features from the data warehouse (MinIO) into the fast Redis cache.

---

## 4. Inference Integration

Within the `vision-service` or `embedding-service` FastAPI application, the ML engineer simply queries Feast for the required features by ID, completely abstracting away the database logic.

```python
# FastAPI Inference Endpoint
from feast import FeatureStore

store = FeatureStore(repo_path=".")

@app.post("/predict")
async def predict(user_id: int, image_b64: str):
    # 1. Fetch historical features from Redis (Sub-2ms latency)
    features = store.get_online_features(
        features=[
            "user_stats:ctr_30_days",
            "user_stats:purchase_count"
        ],
        entity_rows=[{"user_id": user_id}]
    ).to_dict()
    
    # 2. Process image through Triton
    tensor = preprocess_image(image_b64)
    
    # 3. Combine CNN output with historical features for final MLP layer
    final_input = concatenate(tensor, features["ctr_30_days"])
    
    # ...
```

---

## Next Steps

Proceed to `42-model-drift-evidently.md` to monitor the statistical distribution of these incoming features.
