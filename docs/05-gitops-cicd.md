# GitOps and CI/CD Strategy

**Component:** GitHub Actions + ArgoCD  
**Objective:** Automated container builds and GitOps-based k3s deployments  
**Namespace:** argocd  

---

## Prerequisites

Verify core infrastructure components:

```bash
kubectl get nodes
kubectl get deployments -n ml-workloads
kubectl get namespaces | grep argocd
```

---

## Step 1: CI/CD Architecture Overview

### Pipeline Strategy

- **CI (Continuous Integration):** GitHub Actions.
  - Builds multi-stage Docker images for FastAPI and PyTorch workloads.
  - Pushes artifacts to a container registry (GHCR/Docker Hub).
  - Tags images via semantic versioning and Git SHA.
- **CD (Continuous Deployment):** ArgoCD.
  - Monitors the Git repository for drift.
  - Synchronizes cluster state automatically.
  - Provides declarative rollback capabilities.

### Architecture Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitHub Repository                         │
│  Source Code + Kubernetes Manifests (YAML)                      │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              │                               │
              ▼                               ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│   GitHub Actions (CI)    │    │   ArgoCD (CD)             │
│  - Docker Build          │    │  - Git Repository Watch  │
│  - Push to Registry      │    │  - k3s Cluster Sync      │
│  - Security Scanning     │    │  - Health Checks          │
└──────────────────────────┘    └──────────────────────────┘
              │                               │
              ▼                               ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│  Container Registry      │    │  k3s Cluster              │
│  (Docker Hub / GHCR)     │    │  - Deployments            │
│  - Image Storage         │    │  - Services               │
│  - Image Tags            │    │  - ConfigMaps             │
└──────────────────────────┘    └──────────────────────────┘
```

---

## Step 2: GitHub Actions CI Pipeline

### Workflow Configuration

```yaml
# .github/workflows/ci-build.yml
name: CI - Build and Push Container Images

on:
  push:
    branches:
      - main
    tags:
      - 'v*'
  pull_request:
    branches:
      - main
  workflow_dispatch:

env:
  REGISTRY: ghcr.io
  IMAGE_NAME_EMBEDDING: embedding-service
  IMAGE_NAME_VISION: vision-service
  IMAGE_NAME_WORKER: background-worker

jobs:
  build-embedding:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata for Docker
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ github.repository }}/${{ env.IMAGE_NAME_EMBEDDING }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=sha,prefix={{branch}}-

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: ./services/embedding
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          platforms: linux/amd64

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ github.repository }}/${{ env.IMAGE_NAME_EMBEDDING }}:${{ github.sha }}
          format: 'sarif'
          output: 'trivy-results.sarif'

      - name: Upload Trivy results to GitHub Security
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: 'trivy-results.sarif'

  build-vision:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata for Docker
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ github.repository }}/${{ env.IMAGE_NAME_VISION }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=sha,prefix={{branch}}-

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: ./services/vision
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          platforms: linux/amd64

  build-worker:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata for Docker
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ github.repository }}/${{ env.IMAGE_NAME_WORKER }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=sha,prefix={{branch}}-

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: ./services/worker
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          platforms: linux/amd64
```

### Reference Dockerfile (Embedding Service)

```dockerfile
# services/embedding/Dockerfile
FROM python:3.11-slim as builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM python:3.11-slim

WORKDIR /app
COPY --from=builder /root/.local /root/.local
ENV PATH=/root/.local/bin:$PATH

COPY gpu_memory_config.py .
COPY main.py .

RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Requirements

```txt
# services/embedding/requirements.txt
fastapi==0.104.1
uvicorn[standard]==0.24.0
torch==2.1.0
sentence-transformers==2.2.2
pydantic==2.5.0
```

---

## Step 3: ArgoCD Installation

Register the Helm repository and deploy ArgoCD:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  --namespace argocd \
  --version 5.51.0 \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=30080 \
  --set configs.credentialTemplates.github-creds.url=https://github.com \
  --set configs.credentialTemplates.github-creds.username=<github-username> \
  --set configs.credentialTemplates.github-creds.password=<github-token>
```

Verify deployment state:

```bash
kubectl get pods -n argocd
kubectl get svc -n argocd
```

Access the UI using the auto-generated password:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

---

## Step 4: Application Manifests

### App of Apps (Root Manifest)

```yaml
# manifests/argocd/app-of-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gpu-orchestration-root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/<your-username>/gpu-orchestration.git
    targetRevision: main
    path: manifests/argocd
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
```

### GPU Infrastructure Component

```yaml
# manifests/argocd/gpu-infrastructure-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gpu-infrastructure
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-username>/gpu-orchestration.git
    targetRevision: main
    path: manifests/gpu-infrastructure
  destination:
    server: https://kubernetes.default.svc
    namespace: gpu-infrastructure
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

---

## Step 5: Application Deployment

Inject the root manifest to trigger the cascade sync:

```bash
kubectl apply -f manifests/argocd/app-of-apps.yaml
kubectl get applications -n argocd
kubectl get application gpu-infrastructure -n argocd -o yaml | grep -A 5 syncStatus
```

---

## Step 6: Image Updater Configuration

Deploy the ArgoCD Image Updater to automate deployments upon container registry updates:

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater
```

```yaml
# manifests/argocd/image-updater-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  log.level: debug
  argocd.server.address: argocd-server.argocd.svc
  argocd.server.insecure: "true"
  registries: |
    - name: GitHub Container Registry
      api_url: https://ghcr.io
      ping_url: https://ghcr.io/v2/
      credentials: pullsecret:ghcr-creds
  prefix: ghcr.io/<your-username>
  applications: |
    - name: ml-workloads
      images:
      - image_name: ghcr.io/<your-username>/embedding-service
        update_strategy: latest
```

Apply and restart:

```bash
kubectl apply -f manifests/argocd/image-updater-configmap.yaml
kubectl rollout restart deployment argocd-image-updater -n argocd
```

---

## Troubleshooting

### GitHub Actions Permission Denied
**Condition:** Build fails at "Log in to Container Registry".
**Resolution:** Navigate to Settings → Actions → General → Workflow permissions, and enable "Read and write permissions".

### ArgoCD Private Repository Access Failure
**Condition:** Application status is "Unknown".
**Resolution:** Verify the `github-creds` secret maps properly to the `configs.credentialTemplates` stanza in the Helm values.

### Image Updater Sync Failure
**Condition:** New images pushed to GHCR but deployments do not roll out.
**Resolution:** Inspect the image updater logs:
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater
```

---

## Next Steps

Proceed to `06-finops-roi-analysis.md` to establish cost tracking mechanisms and ROI calculations.
