# Developer Experience (JupyterHub Workspaces)

**Component:** Cloud Workspaces  
**Objective:** Provide isolated, interactive data science environments on cluster hardware  
**Architecture:** JupyterHub on Kubernetes (Zero to JupyterHub)  

---

## 1. The Local Development Bottleneck

As the infrastructure shifts to a centralized bare-metal cluster, Data Scientists face a workflow disconnect. They cannot run massive PyTorch training loops or load 30GB foundation models on their local MacBook laptops. 

Manually building Docker images and pushing them to ArgoCD just to test a 5-line Python script modification is infuriatingly slow. Engineers need interactive REPL environments (Jupyter Notebooks) executing *directly* on the cluster hardware, with access to the same CephFS storage and Time-Sliced GPUs as production workloads.

---

## 2. JupyterHub Architecture

**JupyterHub** provisions and manages multi-user Jupyter environments. Using the Kubernetes Spawner (`KubeSpawner`), JupyterHub dynamically spins up a dedicated Kubernetes Pod for every authenticated user.

1. User logs into a web portal (integrated with corporate OAuth).
2. User selects a hardware profile (e.g., "1 CPU, 4GB RAM" vs. "1 GPU Slice, 16GB RAM").
3. JupyterHub spawns an isolated Pod and routes a personal URL to it via the Ingress controller.
4. If idle for >60 minutes, JupyterHub kills the Pod to reclaim the hardware (saving VRAM).

---

## 3. Implementation (Zero to JupyterHub)

Deploy via the official Helm chart.

```bash
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update
```

### 3.1 Profile Configuration

Define the hardware tiers available to developers in the `values.yaml` configuration.

```yaml
# jupyterhub-values.yaml
hub:
  config:
    Authenticator:
      # e.g., GitHub, Google, or Active Directory OIDC
      class: dummy
      
singleuser:
  # Base image containing PyTorch, Pandas, and CUDA libraries
  image:
    name: jupyter/pytorch-notebook
    tag: cuda12-latest
  
  # Persistent storage for the user's notebooks (survives pod restarts)
  storage:
    type: dynamic
    capacity: 20Gi
    
  profileList:
    - display_name: "Standard CPU (EDA & SQL)"
      description: "For basic data exploration."
      default: true
      kubespawner_override:
        cpu_limit: 2
        mem_limit: 8G
        
    - display_name: "GPU Time-Slice (Model Prototyping)"
      description: "Allocates 1 logical GPU replica (3.2GB VRAM)."
      kubespawner_override:
        cpu_limit: 4
        mem_limit: 16G
        extra_resource_limits:
          nvidia.com/gpu: "1"
```

### 3.2 Deployment

```bash
helm install jupyterhub jupyterhub/jupyterhub \
  --namespace jupyter \
  --create-namespace \
  --values jupyterhub-values.yaml
```

---

## 4. Workflow Integration

With JupyterHub deployed:
1. **Data Access:** Data Scientists can directly import datasets from the local MinIO/CephFS without downloading them over the internet.
2. **Experimentation:** They prototype the model interactively.
3. **Tracking:** Because they are on the cluster, they can point MLflow directly to `http://mlflow.data-plane.svc.cluster.local:5000` to log their experimental metrics instantly.
4. **Transition to Prod:** Once the notebook logic is finalized, it is converted into a standard Python script, committed to Git, and handed over to the Argo Workflows (`54-ml-pipeline-orchestration.md`) DAG.

---

**End of Platform Engineering Documentation Series.**
