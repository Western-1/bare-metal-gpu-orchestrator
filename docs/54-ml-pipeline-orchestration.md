# ML Pipeline Orchestration (Argo Workflows)

**Component:** Directed Acyclic Graphs (DAG)  
**Objective:** Automate the end-to-end Machine Learning lifecycle  
**Architecture:** Argo Workflows (or Kubeflow Pipelines)  

---

## 1. The Orchestration Gap

Currently, our infrastructure houses best-in-class individual components:
- **DVC** (`46`) manages the data.
- **Ray** (`21`) executes the training.
- **MLflow** (`18`) tracks the models.
- **ArgoCD** (`05`) deploys the HTTP endpoints.

However, executing these components requires a human engineer to manually trigger scripts in sequence. A true Platform Engineering environment requires a mathematical graph (DAG) to execute these steps autonomously, handle retries, and pass artifacts between stages.

---

## 2. Argo Workflows Architecture

**Argo Workflows** is a Kubernetes-native workflow engine. Every step in the workflow runs as a distinct Pod. When step A finishes successfully, step B is triggered automatically. 

*(Note: Kubeflow Pipelines utilizes Argo Workflows under the hood. For bare-metal agility, deploying raw Argo Workflows reduces unnecessary overhead).*

---

## 3. Defining the ML DAG

The workflow definition is committed to Git and can be triggered via a Webhook (e.g., a new dataset is pushed to MinIO) or on a Cron schedule.

```yaml
# ml-training-pipeline.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: vision-training-pipeline-
  namespace: ml-workloads
spec:
  entrypoint: ml-pipeline
  templates:
  - name: ml-pipeline
    dag:
      tasks:
      # Step 1: Fetch Data
      - name: fetch-data
        template: run-dvc-pull
        
      # Step 2: Train Model (Depends on Step 1)
      - name: train-model
        dependencies: [fetch-data]
        template: submit-ray-job
        
      # Step 3: Evaluate Model (Depends on Step 2)
      - name: evaluate-model
        dependencies: [train-model]
        template: run-eval-script
        
      # Step 4: Promote to Production (Depends on Step 3)
      - name: promote-model
        dependencies: [evaluate-model]
        template: trigger-argocd-sync

  # Example Template Definition for Step 2
  - name: submit-ray-job
    container:
      image: rayproject/ray:latest
      command: [sh, -c]
      args: ["ray job submit --address http://kuberay-head:8265 -- python train.py"]
```

---

## 4. Operational Advantages

1. **Idempotency:** If the `evaluate-model` step fails due to a network timeout, Argo Workflows can automatically retry just that specific step without having to re-run the expensive 10-hour `train-model` step.
2. **Parallelism:** If optimizing multiple hyperparameters (`47-hyperparameter-tuning.md`), Argo can fan-out 10 parallel training tasks simultaneously, wait for all to complete, and fan-in the results to select the best model.
3. **Artifact Passing:** Argo automatically persists outputs (e.g., the final `.pt` weights file) from one pod's local filesystem to MinIO, and mounts it into the next pod in the DAG.

---

## Next Steps

Proceed to `55-scale-to-zero-knative.md` to implement Serverless CPU/GPU resource optimization.
