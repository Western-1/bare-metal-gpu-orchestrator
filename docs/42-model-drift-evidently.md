# Model & Data Drift (Evidently AI)

**Component:** Post-Deployment Monitoring  
**Objective:** Detect mathematical degradation of models over time  
**Architecture:** Evidently AI + Prometheus / Grafana  

---

## 1. The Silent Failure of Machine Learning

Traditional software fails loudly (e.g., HTTP 500, SegFault, OOM). Machine Learning models fail silently. 

If an NLP classifier was trained on data from 2024, but the linguistic patterns of users change drastically in 2026, the FastAPI endpoint will still return HTTP 200, and the GPU will still execute perfectly. However, the business metrics (accuracy) will plummet. This phenomenon is known as **Model Drift** or **Data Drift**.

---

## 2. Evidently AI Architecture

To monitor this, we deploy **Evidently AI**, an open-source framework that continuously calculates statistical distances (e.g., Wasserstein distance, Kullback-Leibler divergence) between the training dataset (Reference Data) and the live production inference inputs (Current Data).

### 2.1 The Shadow Deployment Topology

To prevent drift calculations from bottlenecking the primary GPU inference loop, telemetry is collected asynchronously.

1. The FastAPI endpoint processes the prediction.
2. It pushes a payload (Inputs + Output) to an asynchronous Redis Queue or Kafka topic.
3. A background Pod consumes this topic, runs the Evidently statistical tests, and exposes the drift metrics to Prometheus.

---

## 3. Implementation

### 3.1 Telemetry Collection

```python
# Inside FastAPI Background Task
import json
from redis import Redis

redis_client = Redis(host='redis-master')

async def log_inference_telemetry(inputs: list, prediction: int):
    payload = {
        "feature_1": inputs[0],
        "feature_2": inputs[1],
        "prediction": prediction
    }
    # Push to asynchronous stream
    redis_client.xadd("inference_telemetry", payload)
```

### 3.2 Drift Calculation Worker

The background worker periodically pulls batches from the stream and calculates the drift score.

```python
import pandas as pd
from evidently.report import Report
from evidently.metric_preset import DataDriftPreset

def calculate_drift(current_data_df):
    # Load the baseline training data distribution
    reference_data_df = pd.read_parquet("s3://ml-data/reference_dataset.parquet")
    
    report = Report(metrics=[DataDriftPreset()])
    report.run(reference_data=reference_data_df, current_data=current_data_df)
    
    results = report.as_dict()
    
    # Expose to Prometheus metrics endpoint
    drift_gauge.set(results["metrics"][0]["result"]["share_of_drifted_columns"])
```

---

## 4. Alerting Rules

When Data Drift is detected, it acts as a trigger to automatically retrain the model via KubeRay, completing the autonomous MLOps loop.

```yaml
groups:
- name: ml-drift-alerts
  rules:
  - alert: SevereDataDrift
    expr: evidently_share_of_drifted_columns > 0.30
    for: 1h
    annotations:
      summary: "Data Drift Detected"
      description: "Over 30% of input features have drifted statistically from the training baseline. Initiate KubeRay retraining pipeline."
```

---

## Next Steps

Proceed to `43-confidential-computing-tee.md` to secure model weights in memory.
