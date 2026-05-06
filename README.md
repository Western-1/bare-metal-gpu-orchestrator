# GPU Multi-Tenancy on Consumer Hardware: Time-Slicing Architecture

![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.29-blue?logo=kubernetes&logoColor=white)
![NVIDIA](https://img.shields.io/badge/NVIDIA-RTX_5070_Ti-green?logo=nvidia&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.11+-blue?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-0.104+-teal?logo=fastapi&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-DCGM_Exporter-orange?logo=prometheus&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-yellow)

> **Production-ready GPU orchestration architecture enabling multi-tenant ML inference on bare-metal consumer GPUs via software-based Time-Slicing.**

---

## Executive Summary

Consumer-grade NVIDIA GPUs (RTX series) offer exceptional price-to-performance ratios for machine learning workloads but lack hardware-level multi-tenancy features like MIG (Multi-Instance GPU). This creates a fundamental challenge: **GPU underutilization**. A single RTX 5070 Ti (16GB VRAM) typically runs one ML service, leaving the majority of compute resources idle.

This project implements a **software-based Time-Slicing architecture** that splits one physical GPU into four logical replicas, enabling concurrent execution of multiple ML workloads (FastAPI + PyTorch services) on a single consumer GPU. The architecture achieves:

- **4× GPU utilization** through temporal compute slicing
- **Zero OOM kills** via PyTorch VRAM fractioning and Kubernetes memory limits
- **Production-grade observability** with DCGM Exporter, Prometheus, and Grafana
- **Bare-metal simplicity** using k3s (lightweight Kubernetes) instead of enterprise-grade clusters

This solution is ideal for edge computing, home labs, and cost-conscious ML teams seeking to maximize GPU ROI without enterprise hardware investments.

---

## Key Features

### 🚀 **Zero OOM Architecture**
- **PyTorch VRAM Fractioning**: Each pod limits VRAM allocation to 20% (3.2GB) via `torch.cuda.set_per_process_memory_fraction`
- **Kubernetes Memory Limits**: System RAM constrained to 4Gi per pod with 2Gi requests
- **Model Pre-loading**: Warmup forward pass allocates VRAM on startup, preventing runtime spikes
- **Strict Isolation**: 7GB VRAM headroom reserved for fragmentation and driver overhead

### ⚡ **GPU Time-Slicing**
- **4 Logical Replicas**: Single RTX 5070 Ti presented as `nvidia.com/gpu: 4` to Kubernetes scheduler
- **10ms Temporal Slices**: Default time-slice duration optimized for inference workloads
- **1:1 Pod Mapping**: Enforced via `failRequestsGreaterThanOne: true` to prevent over-subscription
- **Consumer GPU Compatible**: Works on RTX series without MIG hardware support

### 📊 **DCGM Observability**
- **Real-Time GPU Telemetry**: DCGM Exporter collects VRAM usage, GPU utilization, temperature, and power metrics every 15 seconds
- **Prometheus Integration**: ServiceMonitor auto-discovery for seamless metric scraping
- **Grafana Dashboards**: Pre-built NVIDIA GPU dashboard + custom Time-Slicing visualization
- **Alerting Rules**: Automated alerts for VRAM >75%, GPU saturation >95%, and thermal throttling

### 🔧 **Bare-Metal Simplicity**
- **k3s Lightweight Kubernetes**: Single-node cluster with <512MB memory footprint
- **Docker Runtime**: Native Docker integration with NVIDIA Container Toolkit
- **No Enterprise Dependencies**: Runs on Ubuntu 24.04 LTS without vCenter, load balancers, or cloud providers
- **Helm-Based Deployments**: Device Plugin, DCGM Exporter, and kube-prometheus-stack via Helm charts

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Bare-Metal Node (Ubuntu 24.04)               │
│  AMD Ryzen 7 7800X3D | 32GB RAM | NVIDIA RTX 5070 Ti (16GB)    │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   k3s v1.29  │    │  Docker v27  │    │ NVIDIA Driver│
│  (Scheduler) │    │  (Runtime)   │    │    v535+     │
└──────────────┘    └──────────────┘    └──────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              ▼
                    ┌──────────────────┐
                    │ NVIDIA Container │
                    │      Toolkit     │
                    └──────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  NVIDIA      │    │  Time-Slice  │    │  Workloads   │
│ Device Plugin│───▶│  ConfigMap   │───▶│  (FastAPI +  │
│  (DaemonSet) │    │  (4 Replicas)│    │   PyTorch)   │
└──────────────┘    └──────────────┘    └──────────────┘
        │                                       │
        └─────────────────────┬─────────────────┘
                              ▼
                    ┌──────────────────┐
                    │  DCGM Exporter   │
                    │  (DaemonSet)     │
                    └──────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  Prometheus +    │
                    │     Grafana      │
                    └──────────────────┘
```

### Technology Stack

| **Layer** | **Component** | **Version** | **Purpose** |
|-----------|---------------|-------------|-------------|
| **OS** | Ubuntu 24.04 LTS | 24.04 | Base operating system |
| **Container Runtime** | Docker | 27.0+ | Container engine with GPU passthrough |
| **Kubernetes** | k3s | v1.29+k3s1 | Lightweight single-node cluster |
| **GPU Virtualization** | NVIDIA Device Plugin | v0.15.0 | Advertises GPU resources to scheduler |
| **Time-Slicing** | ConfigMap | Custom | Splits 1 GPU into 4 logical replicas |
| **Workloads** | FastAPI + PyTorch | 0.104+ / 2.1+ | ML inference services |
| **Observability** | DCGM Exporter | 3.3.0-3.1.0 | GPU telemetry collection |
| **Metrics** | Prometheus | Latest | Time-series database |
| **Visualization** | Grafana | Latest | Dashboard and alerting |
| **Package Manager** | Helm | v3.15+ | Kubernetes package management |

---

## Documentation Hub

This repository includes comprehensive, production-ready documentation in the `docs/` directory. Each document provides step-by-step methodologies, exact bash commands, YAML configurations, and code snippets.

### 📚 **Start Here: Documentation Index**

**[docs/00-index.md](docs/00-index.md)** — Central hub with relationship matrix, Mermaid.js architecture diagrams, and reading guide for new engineers.

### 🔧 **Implementation Guides**

1. **[docs/01-infrastructure-setup.md](docs/01-infrastructure-setup.md)**  
   Bare-metal node preparation: NVIDIA driver installation, Docker runtime, NVIDIA Container Toolkit, k3s deployment with Docker runtime, and verification steps.

2. **[docs/02-gpu-time-slicing-config.md](docs/02-gpu-time-slicing-config.md)**  
   GPU virtualization configuration: NVIDIA Device Plugin deployment via Helm, Time-Slicing ConfigMap creation, scheduler verification, and multi-pod concurrency testing.

3. **[docs/03-workloads-and-memory.md](docs/03-workloads-and-memory.md)**  
   ML workload deployment: Kubernetes Deployment templates with GPU requests, PyTorch memory fractioning code, FastAPI service configuration, and OOM prevention strategies.

4. **[docs/04-observability-dcgm.md](docs/04-observability-dcgm.md)**  
   Observability stack: DCGM Exporter deployment, Prometheus and Grafana setup via Helm, critical PromQL queries for GPU monitoring, and alerting rule configuration.

5. **[docs/05-gitops-cicd.md](docs/05-gitops-cicd.md)**  
   GitOps and CI/CD: Automated container image builds, security scanning with GitHub Actions, and ArgoCD deployment pipeline.

6. **[docs/06-finops-roi-analysis.md](docs/06-finops-roi-analysis.md)**  
   Financial analysis: Cloud vs. bare-metal cost comparison, ROI calculations, and carbon footprint metrics.

7. **[docs/07-performance-benchmarks.md](docs/07-performance-benchmarks.md)**  
   Performance testing: Locust load testing for APIs, performance metrics, and capacity planning.

8. **[docs/08-hardware-power-optimization.md](docs/08-hardware-power-optimization.md)**  
   Power optimization: GreenOps practices, NVIDIA power capping, thermal target configuration, and energy savings.

9. **[docs/09-security-and-network-isolation.md](docs/09-security-and-network-isolation.md)**  
   Security hardening: Kubernetes NetworkPolicy for zero-trust isolation, RBAC, and pod security standards.

10. **[docs/10-disaster-recovery.md](docs/10-disaster-recovery.md)**  
    Disaster recovery: Velero automated backups to MinIO, RTO/RPO objectives, and complete cluster recovery.

---

## Prerequisites

### Hardware Requirements

| **Component** | **Minimum** | **Recommended** | **Notes** |
|--------------|-------------|-----------------|-----------|
| **CPU** | 8 cores | 16 cores (AMD Ryzen 7 7800X3D) | For concurrent pod execution |
| **RAM** | 16GB | 32GB | System RAM for Kubernetes and workloads |
| **GPU** | NVIDIA RTX 3060 (12GB) | NVIDIA RTX 5070 Ti (16GB) | Consumer GPU without MIG support |
| **Storage** | 100GB SSD | 500GB NVMe SSD | For container images and logs |

### Software Requirements

- **Operating System**: Ubuntu 24.04 LTS (fresh installation recommended)
- **NVIDIA Driver**: Version 535+ (supports CUDA 12.x)
- **Internet Access**: Required for Helm chart downloads and container image pulls
- **User Privileges**: sudo access for system-level installations

### Supported GPU Models

This architecture is tested and verified on:
- ✅ NVIDIA RTX 5070 Ti (16GB)
- ✅ NVIDIA RTX 4090 (24GB)
- ✅ NVIDIA RTX 3090 (24GB)
- ✅ NVIDIA RTX 3060 (12GB)

*Other RTX series GPUs with 12GB+ VRAM should work but may require memory fraction adjustments.*

---

## Quick Start

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd devops
   ```

2. **Read the documentation index**
   ```bash
   # Start here for architecture overview and reading guide
   cat docs/00-index.md
   ```

3. **Follow the implementation guides in order**
   ```bash
   # Step 1: Infrastructure setup
   # Follow docs/01-infrastructure-setup.md
   
   # Step 2: GPU Time-Slicing configuration
   # Follow docs/02-gpu-time-slicing-config.md
   
   # Step 3: Workload deployment
   # Follow docs/03-workloads-and-memory.md
   
   # Step 4: Observability setup
   # Follow docs/04-observability-dcgm.md
   ```

---

## Project Status

- ✅ **Infrastructure Setup**: Complete and verified
- ✅ **GPU Time-Slicing**: Configured with 4 logical replicas
- ✅ **Workload Deployment**: FastAPI + PyTorch services with memory management
- ✅ **Observability**: DCGM Exporter + Prometheus + Grafana operational
- ✅ **Documentation**: Comprehensive, production-ready guides

---

## Contributing

This is a reference architecture for GPU multi-tenancy on consumer hardware. Contributions are welcome in the form of:
- Documentation improvements
- Additional GPU model compatibility testing
- Performance benchmarking data
- Alternative workload examples (e.g., TensorFlow, JAX)

---

## License

MIT License — See LICENSE file for details.

---

## Acknowledgments

- **NVIDIA** for the Device Plugin and DCGM Exporter projects
- **k3s** project for lightweight Kubernetes
- **Prometheus** and **Grafana** communities for observability tooling
- **FastAPI** and **PyTorch** teams for exceptional ML frameworks

---

## Contact

For questions or discussions about this architecture, please open an issue in the repository.

---

**Built with ❤️ for the MLOps community — Maximizing GPU ROI on consumer hardware.**
