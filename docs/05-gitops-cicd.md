# GitOps and CI/CD Strategy

**Component:** GitHub Actions + ArgoCD  
**Objective:** Automated container builds and GitOps-based k3s deployments  
**Namespace:** argocd  

---

## Prerequisites

Ensure core infrastructure is complete from `01-infrastructure-setup.md`:

```bash
# Verify k3s is running
kubectl get nodes

# Verify workloads are deployed
kubectl get deployments -n ml-workloads

# Verify argocd namespace exists (created in infrastructure setup)
kubectl get namespaces | grep argocd
```

---

## Step 1: CI/CD Architecture Overview

### Pipeline Strategy

This project implements a hybrid CI/CD approach:

- **CI (Continuous Integration):** GitHub Actions for container image builds
  - Triggers: Push to main branch, pull requests, manual workflow dispatch
  - Build: Multi-stage Docker builds for FastAPI + PyTorch services
  - Push: Container registry (Docker Hub, GHCR, or private registry)
  - Tagging: Semantic versioning + Git SHA for traceability

- **CD (Continuous Deployment):** ArgoCD for GitOps-based k3s deployments
  - Sync Strategy: Automatic sync on Git repository changes
  - Self-Healing: Automatic drift detection and correction
  - Rollback: One-click rollback to previous Git commits
  - Notifications: Slack/email alerts on deployment status

### Architecture Diagram

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

Create the GitHub Actions workflow for container builds:

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

### Dockerfile for Embedding Service

```dockerfile
# services/embedding/Dockerfile
FROM python:3.11-slim as builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir --user -r requirements.txt

# Runtime stage
FROM python:3.11-slim

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /root/.local /root/.local

# Ensure scripts in .local are usable
ENV PATH=/root/.local/bin:$PATH

# Copy application code
COPY gpu_memory_config.py .
COPY main.py .

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Requirements.txt

```txt
# services/embedding/requirements.txt
fastapi==0.104.1
uvicorn[standard]==0.24.0
torch==2.1.0
sentence-transformers==2.2.2
pydantic==2.5.0
```

---

## Step 3: Install ArgoCD on k3s

### Add ArgoCD Helm Repository

```bash
# Add ArgoCD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

### Install ArgoCD

```bash
# Install ArgoCD (namespace already created in 01-infrastructure-setup.md)
helm install argocd argo/argo-cd \
  --namespace argocd \
  --version 5.51.0 \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=30080 \
  --set configs.credentialTemplates.github-creds.url=https://github.com \
  --set configs.credentialTemplates.github-creds.username=<github-username> \
  --set configs.credentialTemplates.github-creds.password=<github-token>
```

**Helm Values Explained:**
- `server.service.type=NodePort`: Expose ArgoCD UI via NodePort for bare-metal access
- `server.service.nodePortHttp=30080`: Specific NodePort for ArgoCD UI
- `configs.credentialTemplates.github-creds`: GitHub credentials for private repository access

### Verify ArgoCD Installation

```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Expected output:
# NAME                                                READY   STATUS    RESTARTS   AGE
# argocd-application-controller-0                      1/1     Running   0          30s
# argocd-applicationset-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
# argocd-notifications-controller-xxxxxxxxxx-xxxxx    1/1     Running   0          30s
# argocd-redis-xxxxxxxxxx-xxxxx                       1/1     Running   0          30s
# argocd-repo-server-xxxxxxxxxx-xxxxx                1/1     Running   0          30s
# argocd-server-xxxxxxxxxx-xxxxx                      1/1     Running   0          30s

# Check ArgoCD service
kubectl get svc -n argocd

# Expected output:
# NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
# argocd-server NodePort    10.x.x.x         <none>        80:30080/TCP,443:30443/TCP   30s
```

### Access ArgoCD UI

```bash
# Get initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d

# Access ArgoCD UI
# URL: http://<node-ip>:30080
# Username: admin
# Password: <output from above command>
```

---

## Step 4: Create ArgoCD Application Manifests

### GPU Infrastructure Application

```yaml
# manifests/argocd/gpu-infrastructure-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gpu-infrastructure
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
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
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### ML Workloads Application

```yaml
# manifests/argocd/ml-workloads-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ml-workloads
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/<your-username>/gpu-orchestration.git
    targetRevision: main
    path: manifests/ml-workloads
  destination:
    server: https://kubernetes.default.svc
    namespace: ml-workloads
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### Monitoring Application

```yaml
# manifests/argocd/monitoring-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/<your-username>/gpu-orchestration.git
    targetRevision: main
    path: manifests/monitoring
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### App of Apps (Parent Application)

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

---

## Step 5: Apply ArgoCD Applications

### Apply Applications to k3s

```bash
# Apply the App of Apps
kubectl apply -f manifests/argocd/app-of-apps.yaml

# Verify applications are created
kubectl get applications -n argocd

# Expected output:
# NAME                        SYNC STATUS   HEALTH STATUS
# gpu-orchestration-root      Synced       Healthy
# gpu-infrastructure          Synced       Healthy
# ml-workloads                Synced       Healthy
# monitoring                  Synced       Healthy
```

### Verify Sync Status

```bash
# Check application sync status
kubectl get application gpu-infrastructure -n argocd -o yaml | grep -A 5 syncStatus

# Check application health
kubectl get application ml-workloads -n argocd -o yaml | grep -A 5 healthStatus
```

---

## Step 6: Configure Image Updater

### Install ArgoCD Image Updater

```bash
# Install ArgoCD Image Updater
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

# Verify installation
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater
```

### Configure Image Updater

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
      - image_name: ghcr.io/<your-username>/vision-service
        update_strategy: latest
```

### Apply Image Updater Configuration

```bash
# Apply configuration
kubectl apply -f manifests/argocd/image-updater-configmap.yaml

# Restart image updater
kubectl rollout restart deployment argocd-image-updater -n argocd
```

---

## Step 7: Configure Notifications

### Install ArgoCD Notifications

```bash
# Install ArgoCD Notifications
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/notifier-installation.yaml

# Verify installation
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-notifications
```

### Configure Slack Notifications

```yaml
# manifests/argocd/notifications-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  context: |
    argocdUrl: http://argocd-server.argocd.svc
  service.slack: |
    token: $slack-token
  subscriptions: |
    - recipients:
      - slack:test-channel
      triggers:
      - on-sync-succeeded
      - on-sync-failed
      - on-sync-status-unknown
  template.app-sync-succeeded.slack: |
    message: |
      Application {{.app.metadata.name}} sync succeeded
      {{if .app.operation}} initiated by {{.app.operation.initiatedBy.username}}{{end}}
    slack:
      attachments: |
        [{
          "title": "{{ .app.metadata.name}}",
          "color": "#18be52",
          "fields": [
            {
              "title": "Sync Status",
              "value": "{{ .app.status.sync.status }}",
              "short": true
            },
            {
              "title": "Repository",
              "value": "{{ .app.spec.source.repoURL }}",
              "short": true
            }
          ]
        }]
  template.app-sync-failed.slack: |
    message: |
      Application {{.app.metadata.name}} sync failed
      {{if .app.operation}} initiated by {{.app.operation.initiatedBy.username}}{{end}}
    slack:
      attachments: |
        [{
          "title": "{{ .app.metadata.name }}",
          "color": "#ff0000",
          "fields": [
            {
              "title": "Sync Status",
              "value": "{{ .app.status.sync.status }}",
              "short": true
            },
            {
              "title": "Error",
              "value": "{{ .app.status.sync.operationState.message }}",
              "short": false
            }
          ]
        }]
```

### Apply Notifications Configuration

```bash
# Apply configuration
kubectl apply -f manifests/argocd/notifications-configmap.yaml

# Create Slack token secret
kubectl create secret generic argocd-notifications-secret \
  -n argocd \
  --from-literal=slack-token=<your-slack-bot-token>
```

---

## Verification Checklist

### ✅ CI Pipeline Verification

```bash
# 1. GitHub Actions workflow triggers on push
# Push a change to main branch and verify workflow runs in GitHub Actions tab

# 2. Container images are pushed to registry
# Check GitHub Container Registry for new images

# 3. Security scanning runs successfully
# Check GitHub Security tab for Trivy results
```

### ✅ ArgoCD Installation Verification

```bash
# 4. ArgoCD pods are running
kubectl get pods -n argocd
# Expected: All pods in Running state

# 5. ArgoCD UI is accessible
# Access http://<node-ip>:30080 and login with admin credentials

# 6. Applications are created
kubectl get applications -n argocd
# Expected: 4 applications listed
```

### ✅ GitOps Sync Verification

```bash
# 7. Applications are synced
kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\n"}{end}'
# Expected: All applications show "Synced"

# 8. Self-healing works
# Manually modify a deployment in k3s and verify ArgoCD reverts the change
kubectl edit deployment embedding-service -n ml-workloads
# Change replicas to 2
# Wait 30 seconds and verify it reverts to 1
```

---

## Troubleshooting

### Issue: GitHub Actions fails with permission denied

**Symptom:** Workflow fails at "Log in to Container Registry" step.

**Solution:**
```bash
# Verify GitHub Actions permissions in repository settings
# Settings → Actions → General → Workflow permissions
# Enable "Read and write permissions"

# Verify GITHUB_TOKEN is available
# GitHub Actions automatically provides this token
```

### Issue: ArgoCD cannot access private GitHub repository

**Symptom:** Application shows "Unknown" sync status with repository access error.

**Solution:**
```bash
# Create GitHub personal access token with repo scope
# Add as secret to ArgoCD

kubectl create secret generic github-creds \
  -n argocd \
  --from-literal=username=<github-username> \
  --from-literal=password=<github-pat>

# Update application to use credentials
kubectl edit application gpu-infrastructure -n argocd
# Add:
# spec:
#   source:
#     repoURL: https://github.com/<username>/repo.git
#     targetRevision: main
#     path: manifests/gpu-infrastructure
```

### Issue: Image Updater not triggering syncs

**Symptom:** New container images pushed but ArgoCD not updating.

**Solution:**
```bash
# Check image updater logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater

# Verify configuration
kubectl get configmap argocd-image-updater-config -n argocd -o yaml

# Check application has image updater annotation
kubectl get application ml-workloads -n argocd -o yaml | grep argocd-image-updater
```

### Issue: Notifications not sending to Slack

**Symptom:** Sync events occur but no Slack notifications received.

**Solution:**
```bash
# Check notifications controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-notifications

# Verify Slack token secret
kubectl get secret argocd-notifications-secret -n argocd -o yaml

# Test notification manually
kubectl exec -n argocd deployment/argocd-notifications-controller -- \
  argocd-notifications trigger app-sync-succeeded ml-workloads
```

---

## Best Practices

### Branch Strategy

- **main**: Production branch with automated deployments
- **develop**: Integration branch for feature testing
- **feature/***: Feature branches with PR-based CI

### Image Tagging Strategy

- **latest**: Latest stable build from main branch
- **vX.Y.Z**: Semantic version tags for releases
- **git-sha**: Git commit SHA for traceability

### GitOps Workflow

1. Developer creates feature branch
2. Developer commits changes and opens PR
3. GitHub Actions runs CI pipeline
4. PR approved and merged to main
5. GitHub Actions builds and pushes images
6. ArgoCD detects Git changes
7. ArgoCD syncs changes to k3s cluster
8. Notifications sent to Slack

---

## Next Steps

With GitOps and CI/CD configured, proceed to:

**Document 6:** `06-finops-roi-analysis.md`

This document covers:
- Cost-benefit analysis of bare-metal vs. cloud GPU instances
- ROI calculations for Time-Slicing architecture
- Monthly cost comparison and savings projections
