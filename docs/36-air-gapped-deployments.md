# Air-Gapped Deployments (Offline AI)

**Component:** Container Registry & Artifact Mirrors  
**Objective:** Execute ML topologies in environments with zero internet connectivity  
**Architecture:** Harbor + HuggingFace Mirroring  

---

## 1. The Air-Gapped Imperative

For defense, critical infrastructure, and highly regulated financial entities, ML clusters must operate in strict "Air-Gapped" topologies. The servers have no route to the public internet.

This invalidates standard workflows:
- Kubernetes cannot pull images from `docker.io` or `ghcr.io`.
- PyTorch/vLLM cannot download models dynamically from `huggingface.co`.
- Ubuntu cannot run `apt-get` for NVIDIA drivers.

---

## 2. Local Container Registry (Harbor)

To provision containers locally, deploy **Harbor**, an enterprise-class container registry with vulnerability scanning capabilities.

### Topology
1. A "Bridge" machine with internet access downloads the required images (e.g., `vllm/vllm-openai`, `rayproject/ray`).
2. The images are saved to a portable physical medium (e.g., encrypted NVMe drive) using `docker save`.
3. The medium is transported to the Air-Gapped cluster.
4. Images are loaded (`docker load`) and pushed to the internal Harbor registry.

### Configuration
Kubernetes Deployments must be refactored to pull from the internal domain, authenticated via `ImagePullSecrets`.

```yaml
# workloads/vllm.yaml
spec:
  imagePullSecrets:
  - name: harbor-credentials
  containers:
  - name: vllm
    # Target the internal registry instead of Docker Hub
    image: harbor.internal.corp/mlops/vllm-openai:latest
```

---

## 3. HuggingFace Offline Mirroring

Models cannot be downloaded at runtime. All required weights, tokenizers, and configuration JSONs must be mirrored to the internal distributed storage array (Ceph/Rook or MinIO).

### Mirroring Script (On Bridge Machine)

Utilize the `huggingface-cli` to download the specific snapshot, omitting unnecessary precision variants (e.g., skipping `fp32` if only `awq` is required).

```bash
# Bridge Machine: Download the model
huggingface-cli download TheBloke/Llama-2-7B-Chat-AWQ \
  --local-dir ./offline-models/Llama-2-7B-Chat-AWQ \
  --local-dir-use-symlinks False
```

### Loading into Air-Gapped Storage

Transfer the `offline-models` directory to the internal CephFS cluster (`/mnt/shared-model-fs/`).

Instruct the inference engines to read strictly from the local mount path, bypassing internet resolution.

```yaml
# vLLM Command Override
    command:
    - "python3"
    - "-m"
    - "vllm.entrypoints.openai.api_server"
    # Provide absolute local path instead of HF repository name
    - "--model"
    - "/models/Llama-2-7B-Chat-AWQ"
```
Ensure the `HF_HUB_OFFLINE=1` environment variable is injected into all PyTorch containers to instantly fail fast on network requests instead of timing out.

---

## Next Steps

Proceed to `37-ha-control-plane.md` to harden the Kubernetes control plane.
