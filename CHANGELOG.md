# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-07-03

### Added
- **Hyper-Scale Enterprise Topologies**: Added extensive documentation (Docs 27-45) covering Triton Inference Server, RAG pipelines, external HashiCorp Vault, air-gapped container deployments, K3s HA Control Planes, Kubecost FinOps, Karmada Federation, and LLM-as-a-Judge evaluations.
- **Open Source Governance**: Added `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, and standard `LICENSE` files.
- **Extreme MLOps Topologies**: Added documentation for Feast Feature Store, Evidently AI Drift detection, SLSA level 3 security, Kepler Energy tracking, and TEE Confidential Computing.

### Changed
- Complete overhaul of all documentation (`docs/00-index.md` through `docs/26`) to enforce strict Senior Staff Engineer architectural tone.
- Deprecated monolithic `ARCHITECTURE.md` in favor of the modular `docs/` structure.

## [1.0.0] - Initial Release

### Added
- Baseline Bare-Metal GPU Time-Slicing infrastructure targeting NVIDIA RTX 5070 Ti.
- FastAPI endpoints with `asyncio.Semaphore` VRAM protection.
- KubeRay and vLLM dynamic batching integrations.
- Prometheus, Grafana, and DCGM observability stack.
- Velero backups and minIO distributed object storage.
