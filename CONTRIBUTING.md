# Contributing to the Bare-Metal GPU Architecture

**Component:** Open Source Governance  
**Objective:** Standardize engineering workflows and pull requests  

---

## 1. Welcome

Thank you for your interest in contributing! This repository operates under strict **Senior Staff Engineer** architectural guidelines. We prioritize deterministic performance, VRAM safety, and infrastructure-as-code (IaC) immutability.

---

## 2. Development Workflow

### Local Verification
Before submitting a Pull Request, you must validate your changes using the local Docker Compose topology.

```bash
# 1. Format all Python code and configurations
make format

# 2. Run the linting suite (Ruff, YAML lint)
make lint

# 3. Spin up the local unified environment
make run-local

# 4. Execute the load test to verify no memory regressions
locust -f tests/locustfile.py --headless -u 10 -r 2 -t 1m
```

### Modifying Documentation
If you are adding a new architectural approach:
1. Create the markdown file in `docs/` using the strict objective tone (no fluff, no emojis).
2. Follow the numerical sequence (e.g., `41-new-feature.md`).
3. Update the relationship matrix in `docs/00-index.md`.
4. Append the new document to the **Advanced MLOps** section of `README.md`.

---

## 3. Pull Request Standards

All PRs must adhere to the following criteria:

- **Commit Messages:** Follow the Conventional Commits specification (e.g., `feat: Add support for PyTorch 2.5`, `fix: Resolve OOM on embedding endpoint`).
- **YAML Formatting:** All Kubernetes manifests must pass `kubeval` or `kube-linter` strict checks.
- **Python Constraints:** Any new inference code MUST implement `asyncio.Semaphore` logic to prevent VRAM saturation.
- **Dependencies:** Do not add dependencies to `services/base/requirements.txt` unless universally required. Use service-specific requirements if applicable.

---

## 4. Hardware Requirements for PR Testing

To test Kubernetes-level changes (e.g., KubeRay, KEDA, Device Plugin mutations), you must have access to a bare-metal node matching the following specifications:
- **OS:** Ubuntu 24.04 LTS
- **GPU:** NVIDIA RTX 3090 / 4090 / 5070 Ti (Minimum 16GB VRAM)
- **Driver:** NVIDIA 535+ (CUDA 12.1+)

If you do not have hardware access, state this clearly in your PR, and a maintainer will execute the integration test suite on the core cluster.
