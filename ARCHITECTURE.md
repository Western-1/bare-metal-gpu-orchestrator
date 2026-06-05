# Architecture Overview

This repository has migrated to a modular, highly detailed architectural documentation format. 

The monolithic architecture document has been deprecated. For the complete, up-to-date documentation covering the entire Bare-Metal GPU Multi-Tenancy infrastructure (from basic setup to Hyper-Scale Enterprise configurations), please see the **[Master Index](docs/00-index.md)**.

## Core Concepts

If you are looking for a quick overview of the architectural philosophy, refer to the following fundamental documents:
1. **[Infrastructure Setup](docs/01-infrastructure-setup.md)**: Why we use k3s on Ubuntu 24.04.
2. **[Time-Slicing Configuration](docs/02-gpu-time-slicing-config.md)**: How we bypass MIG and use NVIDIA Device Plugin to multiplex workloads.
3. **[Workloads & Memory](docs/03-workloads-and-memory.md)**: How we prevent CUDA OOM via `torch.cuda.set_per_process_memory_fraction`.
4. **[Concurrency Limits](docs/19-concurrency-limits.md)**: How we use `asyncio.Semaphore` to queue HTTP traffic safely in RAM.

For all other diagrams, GitOps flows, and MLOps topologies, please navigate to `docs/00-index.md`.
