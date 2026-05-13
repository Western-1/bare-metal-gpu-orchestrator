# ==============================================================================
# Bare-Metal GPU Multi-Tenancy Management
# Abstracting complex k3s, kubectl, and bash commands into elegant targets.
# ==============================================================================

.PHONY: help install-infra deploy-gpu-slice run-workloads monitoring secure-server deploy-gitops deploy-dr clean

# Default target
help:
	@echo "======================================================================"
	@echo " Bare-Metal GPU Multi-Tenancy - Operations"
	@echo "======================================================================"
	@echo ""
	@echo "Available commands:"
	@echo "  make install-infra      - Bootstraps the remote node and configures power limits"
	@echo "  make deploy-gpu-slice   - Deploys NVIDIA Device Plugin and Time-Slicing ConfigMap"
	@echo "  make run-workloads      - Deploys ML workloads and Caching PVCs"
	@echo "  make monitoring         - Deploys Prometheus, Grafana, and DCGM exporter"
	@echo "  make deploy-gitops      - Deploys ArgoCD manifests"
	@echo "  make deploy-dr          - Deploys Velero disaster recovery schedules"
	@echo "  make secure-server      - Applies NetworkPolicies, TLS certs, and Rate Limits"
	@echo "  make deploy-advanced    - Deploys KEDA, KubeRay, OpenTelemetry, and MLflow"
	@echo "  make zero-trust         - Deploys Cloudflare Tunnel and prompts Tailscale setup"
	@echo "  make run-local          - Builds and runs microservices locally via Docker Compose"
	@echo "  make lint               - Runs Ruff to format and lint python code"
	@echo "  make clean              - Tears down all workloads and configurations"
	@echo ""

install-infra:
	@echo "[INFO] Running remote node bootstrap script..."
	@sudo bash scripts/bootstrap-remote-node.sh
	@echo "[INFO] Applying GPU power limits..."
	@sudo bash scripts/apply-power-limit.sh
	@sudo systemctl daemon-reload || true
	@sudo systemctl enable nvidia-power-limit.service || true

deploy-gpu-slice:
	@echo "[INFO] Deploying base namespaces..."
	@kubectl apply -f k8s/00-namespaces.yaml
	@echo "[INFO] Deploying GPU Time-Slicing Configuration..."
	@kubectl apply -f k8s/01-time-slicing-config.yaml
	@helm repo add nvdp https://nvidia.github.io/k8s-device-plugin || true
	@helm repo update
	@helm upgrade -i nvdp nvdp/nvidia-device-plugin \
		--namespace kube-system \
		--set config.name=nvidia-device-plugin-config \
		--set config.default=config.yaml
	@echo "[SUCCESS] GPU Slicing deployed."

run-workloads:
	@echo "[INFO] Deploying ML Workloads (Embedding, Vision, Worker) and Caching PVCs..."
	@kubectl apply -f k8s/02-fastapi-workloads.yaml
	@echo "[SUCCESS] Workloads deployed."

run-local: build-base
	@echo "[INFO] Running microservices locally via Docker Compose..."
	@docker compose up --build

build-base:
	@echo "[INFO] Building base AI Docker image..."
	@docker build --no-cache -t devops-ai-base:latest -f services/base/Dockerfile.base services/base

lint:
	@echo "[INFO] Running Ruff Linter and Formatter..."
	@uvx ruff check . --fix
	@uvx ruff format .
	@echo "[SUCCESS] Code is formatted and clean!"

monitoring:
	@echo "[INFO] Deploying Monitoring Stack rules..."
	@kubectl apply -f k8s/05-monitoring.yaml
	@echo "[SUCCESS] Monitoring rules applied."

deploy-gitops:
	@echo "[INFO] Deploying GitOps infrastructure..."
	@kubectl apply -f k8s/06-argocd.yaml
	@echo "[SUCCESS] GitOps deployed."

deploy-dr:
	@echo "[INFO] Deploying Disaster Recovery schedules..."
	@kubectl apply -f k8s/07-disaster-recovery.yaml
	@echo "[SUCCESS] DR schedules deployed."

secure-server:
	@echo "[INFO] Applying Service Accounts and RBAC..."
	@kubectl apply -f k8s/13-rbac.yaml
	@echo "[INFO] Applying Zero-Trust Network Policies..."
	@kubectl apply -f k8s/03-network-policies.yaml
	@echo "[INFO] Applying Ingress Rate Limiting..."
	@kubectl apply -f k8s/04-ingress-rate-limit.yaml
	@echo "[INFO] Applying TLS Cert-Manager Issuer..."
	@kubectl apply -f k8s/08-cert-manager.yaml
	@echo "[INFO] Applying Grafana Ingress..."
	@kubectl apply -f k8s/09-grafana-ingress.yaml
	@echo "[SUCCESS] Server secured. Ensure UFW rules are configured manually."

zero-trust:
	@echo "[INFO] Setting up Cloudflare Tunnel (Requires TUNNEL_TOKEN in yaml)..."
	@kubectl apply -f k8s/14-cloudflared-tunnel.yaml
	@echo "[INFO] Cloudflare Tunnel deployed."
	@echo "[INFO] To lock down SSH/API, please run: sudo bash scripts/setup-tailscale.sh"

deploy-advanced:
	@echo "[INFO] Deploying Advanced MLOps Infrastructure..."
	@kubectl apply -f k8s/15-keda-autoscaler.yaml
	@kubectl apply -f k8s/16-ray-cluster.yaml
	@kubectl apply -f k8s/17-opentelemetry-tracing.yaml
	@kubectl apply -f k8s/18-mlflow-registry.yaml
	@echo "[SUCCESS] Advanced MLOps Infrastructure deployed."

clean:
	@echo "[WARN] Tearing down workloads and configurations..."
	@kubectl delete -f k8s/02-fastapi-workloads.yaml || true
	@kubectl delete -f k8s/01-time-slicing-config.yaml || true
	@helm uninstall nvdp -n kube-system || true
	@echo "[SUCCESS] Clean complete."
