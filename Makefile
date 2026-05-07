# ==============================================================================
# Bare-Metal GPU Multi-Tenancy Management
# Abstracting complex k3s, kubectl, and bash commands into elegant targets.
# ==============================================================================

.PHONY: help install-infra deploy-gpu-slice run-workloads secure-server clean

# Default target
help:
	@echo "======================================================================"
	@echo " Bare-Metal GPU Multi-Tenancy - Operations"
	@echo "======================================================================"
	@echo ""
	@echo "Available commands:"
	@echo "  make install-infra      - Bootstraps the remote node (Drivers, k3s, containerd)"
	@echo "  make deploy-gpu-slice   - Deploys NVIDIA Device Plugin and Time-Slicing ConfigMap"
	@echo "  make run-workloads      - Deploys ML workloads, PV/PVC caching, and monitoring"
	@echo "  make secure-server      - Applies NetworkPolicies, UFW rules, and API Rate Limits"
	@echo "  make clean              - Tears down all workloads and GPU slicing configurations"
	@echo ""

install-infra:
	@echo "[INFO] Running remote node bootstrap script..."
	@sudo bash scripts/bootstrap-remote-node.sh

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
	@echo "[SUCCESS] GPU Slicing deployed. Verify with: kubectl describe node | grep nvidia.com/gpu"

run-workloads:
	@echo "[INFO] Deploying ML Workloads and Caching PVCs..."
	@kubectl apply -f k8s/02-fastapi-workloads.yaml
	@echo "[SUCCESS] Workloads deployed."

secure-server:
	@echo "[INFO] Applying Zero-Trust Network Policies..."
	@kubectl apply -f k8s/03-network-policies.yaml
	@echo "[INFO] Applying Ingress Rate Limiting..."
	@kubectl apply -f k8s/04-ingress-rate-limit.yaml
	@echo "[SUCCESS] Server secured. Ensure UFW rules are configured manually."

clean:
	@echo "[WARN] Tearing down workloads and GPU slicing..."
	@kubectl delete -f k8s/02-fastapi-workloads.yaml || true
	@kubectl delete -f k8s/01-time-slicing-config.yaml || true
	@helm uninstall nvdp -n kube-system || true
	@echo "[SUCCESS] Clean complete."
