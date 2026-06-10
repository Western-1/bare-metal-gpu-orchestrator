# Bare-Metal GPU Multi-Tenancy Architecture

[![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04%20LTS-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![CUDA 12.1](https://img.shields.io/badge/CUDA-12.1-76B900?style=for-the-badge&logo=nvidia&logoColor=white)](https://developer.nvidia.com/cuda-toolkit)
[![Kubernetes (k3s)](https://img.shields.io/badge/k3s-v1.30-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://k3s.io/)
[![PyTorch 2.4](https://img.shields.io/badge/PyTorch-2.4-EE4C2C?style=for-the-badge&logo=pytorch&logoColor=white)](https://pytorch.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

This repository contains the infrastructure code for deploying a high-throughput, multi-tenant Machine Learning environment on consumer-grade bare-metal hardware. 

By leveraging software-based Time-Slicing, we bypass the need for enterprise MIG (Multi-Instance GPU) hardware, allowing a single NVIDIA GPU (e.g., RTX 5070 Ti) to concurrently serve multiple FastAPI applications, PyTorch inferences, and background Celery workers.

## Architecture

The system is built on a lightweight k3s cluster utilizing the NVIDIA Device Plugin for temporal GPU slicing.

### Core Stack
* **OS**: Ubuntu 24.04 LTS
* **Kubernetes**: k3s (Single-node)
* **Container Runtime**: Docker + NVIDIA Container Toolkit
* **GPU Allocation**: NVIDIA Device Plugin (configured for 4 logical replicas per physical GPU)
* **Workloads**: FastAPI, PyTorch, vLLM
* **Observability**: DCGM Exporter, Prometheus, Grafana, Jaeger
* **Autoscaling**: KEDA
* **Distributed Processing**: KubeRay

### Resource Isolation Strategy
Because consumer GPUs lack hardware memory partitioning, this architecture enforces isolation through software:
1. **PyTorch VRAM Fractioning**: Each pod is restricted to 20% of total VRAM (e.g., 3.2GB on a 16GB card) via `torch.cuda.set_per_process_memory_fraction`.
2. **Concurrency Limits**: FastAPI endpoints are wrapped in `asyncio.Semaphore` to queue excess requests in system RAM, completely eliminating CUDA Out-of-Memory (OOM) crashes under heavy load.
3. **Pre-allocation**: Models perform a warmup forward pass on initialization to reserve their VRAM block before receiving traffic.

## Documentation Directory

All architectural decisions, configurations, and runbooks are documented in the `docs/` directory. 

*Start here:* [docs/00-index.md](docs/00-index.md) provides the complete reading guide and component relationship matrix.

**Infrastructure & Configuration**
* [01-infrastructure-setup.md](docs/01-infrastructure-setup.md) - Bare-metal and k3s preparation.
* [02-gpu-time-slicing-config.md](docs/02-gpu-time-slicing-config.md) - NVIDIA device plugin and ConfigMap setup.
* [03-workloads-and-memory.md](docs/03-workloads-and-memory.md) - Deploying PyTorch workloads safely.
* [11-remote-server-deployment.md](docs/11-remote-server-deployment.md) - Public cloud security and UFW configurations.
* [12-model-caching-pvc.md](docs/12-model-caching-pvc.md) - HostPath PVCs for HuggingFace model caching.

**Operations & Security**
* [04-observability-dcgm.md](docs/04-observability-dcgm.md) - Telemetry, Prometheus, and Grafana.
* [05-gitops-cicd.md](docs/05-gitops-cicd.md) - ArgoCD and GitHub Actions pipelines.
* [08-hardware-power-optimization.md](docs/08-hardware-power-optimization.md) - Power capping and GreenOps.
* [09-security-and-network-isolation.md](docs/09-security-and-network-isolation.md) - NetworkPolicy and zero-trust routing.
* [10-disaster-recovery.md](docs/10-disaster-recovery.md) - Velero backups to MinIO.
* [13-api-gateway-rate-limiting.md](docs/13-api-gateway-rate-limiting.md) - Ingress-level traffic control.

**Advanced MLOps**
* [14-multi-gpu-advanced-topology.md](docs/14-multi-gpu-advanced-topology.md) - Scaling beyond 4 replicas.
* [15-dynamic-batching-vllm.md](docs/15-dynamic-batching-vllm.md) - vLLM and PagedAttention integration.
* [16-multi-lora-architecture.md](docs/16-multi-lora-architecture.md) - Serving dynamic LoRA adapters.
* [17-opentelemetry-tracing.md](docs/17-opentelemetry-tracing.md) - Distributed tracing via Jaeger.
* [18-mlflow-registry.md](docs/18-mlflow-registry.md) - MLflow registry for tracking artifacts.
* [19-concurrency-limits.md](docs/19-concurrency-limits.md) - FastAPI semaphores for OOM protection.
* [20-keda-autoscaling.md](docs/20-keda-autoscaling.md) - Redis queue-based autoscaling for workers.
* [21-ray-distributed-ml.md](docs/21-ray-distributed-ml.md) - KubeRay clusters for distributed ML tasks.
* [22-node-resource-reservation.md](docs/22-node-resource-reservation.md) - Kubelet OS stability reservations.
* [23-model-quantization-strategies.md](docs/23-model-quantization-strategies.md) - 4-bit model quantization.
* [24-log-aggregation-loki.md](docs/24-log-aggregation-loki.md) - Centralized logging with PLG.
* [25-storage-io-optimization.md](docs/25-storage-io-optimization.md) - NVMe RAID for faster model loads.
* [26-gpu-node-maintenance.md](docs/26-gpu-node-maintenance.md) - Zero-downtime maintenance and driver updates.
* [27-distributed-storage-ceph.md](docs/27-distributed-storage-ceph.md) - CephFS for High-Availability model sharing.
* [28-service-mesh-istio.md](docs/28-service-mesh-istio.md) - Istio Sidecars, mTLS, and Circuit Breaking.
* [29-nccl-rdma-networking.md](docs/29-nccl-rdma-networking.md) - RDMA and RoCEv2 for distributed training.
* [30-continuous-profiling-pyroscope.md](docs/30-continuous-profiling-pyroscope.md) - Profiling Python GIL with Pyroscope.
* [31-mig-vs-time-slicing.md](docs/31-mig-vs-time-slicing.md) - Architectural deep-dive of GPU multiplexing.
* [32-spot-instance-preemption.md](docs/32-spot-instance-preemption.md) - Preemption handling for spot instances.
* [33-triton-inference-server.md](docs/33-triton-inference-server.md) - Triton & TensorRT for max throughput.
* [34-rag-vector-database.md](docs/34-rag-vector-database.md) - Qdrant/Milvus setup for RAG pipelines.
* [35-secrets-management-vault.md](docs/35-secrets-management-vault.md) - HashiCorp Vault and External Secrets.
* [36-air-gapped-deployments.md](docs/36-air-gapped-deployments.md) - Offline AI via Harbor registry.
* [37-ha-control-plane.md](docs/37-ha-control-plane.md) - K3s High Availability with external Postgres.
* [38-finops-kubecost-chargeback.md](docs/38-finops-kubecost-chargeback.md) - Granular GPU chargeback with Kubecost.
* [39-multi-cluster-federation.md](docs/39-multi-cluster-federation.md) - Karmada for distributed scaling.
* [40-automated-model-evaluation.md](docs/40-automated-model-evaluation.md) - LLM-as-a-Judge and Ragas CI/CD pipeline.
* [41-feature-store-feast.md](docs/41-feature-store-feast.md) - Feast Feature Store caching.
* [42-model-drift-evidently.md](docs/42-model-drift-evidently.md) - Data drift monitoring.
* [43-confidential-computing-tee.md](docs/43-confidential-computing-tee.md) - TEE hardware encryption for weights.
* [44-slsa-supply-chain-security.md](docs/44-slsa-supply-chain-security.md) - SLSA Level 3 image signing.
* [45-energy-attribution-kepler.md](docs/45-energy-attribution-kepler.md) - eBPF energy consumption tracking.
* [46-data-version-control-dvc.md](docs/46-data-version-control-dvc.md) - Dataset versioning with DVC.
* [47-hyperparameter-tuning.md](docs/47-hyperparameter-tuning.md) - Ray Tune distributed HPO.
* [48-canary-deployments-ab-testing.md](docs/48-canary-deployments-ab-testing.md) - Istio Canary testing models.
* [49-gpu-direct-storage.md](docs/49-gpu-direct-storage.md) - GPUDirect NVMe storage optimization.
* [50-continuous-ml-cml.md](docs/50-continuous-ml-cml.md) - CML reporting in Pull Requests.
* [51-bare-metal-load-balancing.md](docs/51-bare-metal-load-balancing.md) - MetalLB for external traffic.
* [52-llm-guardrails.md](docs/52-llm-guardrails.md) - Real-time NeMo safety guardrails.
* [53-k8s-runtime-security-falco.md](docs/53-k8s-runtime-security-falco.md) - Falco runtime threat detection.
* [54-ml-pipeline-orchestration.md](docs/54-ml-pipeline-orchestration.md) - Argo Workflows for ML DAGs.
* [55-scale-to-zero-knative.md](docs/55-scale-to-zero-knative.md) - Knative serverless scaling.
* [56-jupyterhub-ml-workspaces.md](docs/56-jupyterhub-ml-workspaces.md) - JupyterHub developer workspaces.
* [57-ai-api-gateway-litellm.md](docs/57-ai-api-gateway-litellm.md) - LiteLLM API Gateway and Cost Tracking.
* [58-semantic-caching-redis.md](docs/58-semantic-caching-redis.md) - GPTCache and Redis Semantic Caching.
* [59-structured-json-outputs.md](docs/59-structured-json-outputs.md) - Outlines/Guidance JSON formatting.
* [60-stateful-ai-agents-langgraph.md](docs/60-stateful-ai-agents-langgraph.md) - LangGraph Stateful Agents.
* [CONTRIBUTING.md](CONTRIBUTING.md) - Open source governance and engineering standards.

## Local Development

If you are developing locally without the full k3s cluster, you can spin up the unified Docker environment. This provisions the Redis queue, embedding API, vision API, and background worker.

```bash
# Build the unified uv base image and start the stack
make run-local

# Run formatting and linting
make lint
```

## Production Deployment

Ensure your bare-metal node meets the prerequisites (Ubuntu 24.04, Docker, NVIDIA drivers 535+). 

Deploy components using the provided Makefile targets:

```bash
# 1. Bootstrap node and configure power limits
make install-infra

# 2. Deploy NVIDIA plugin and time-slicing maps
make deploy-gpu-slice

# 3. Deploy monitoring stack (DCGM, Prometheus, Grafana)
make monitoring

# 4. Deploy standard workloads
make run-workloads

# 5. (Optional) Deploy advanced MLOps features
make deploy-advanced
```

## License
MIT License. See LICENSE for details.
