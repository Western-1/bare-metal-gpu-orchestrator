# Bare-Metal GPU Multi-Tenancy Architecture

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
