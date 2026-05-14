# Model Quantization Strategies

**Component:** Model Weights  
**Objective:** Compress foundation models to execute within fractional VRAM boundaries  
**Formats:** AWQ, GPTQ, GGUF  

---

## 1. The VRAM Constraints

In a GPU Time-Slicing topology (e.g., configuring `replicas: 4` on a 16GB RTX 4080/5070 Ti), each pod is constrained to roughly ~3.2GB to ~4GB of VRAM.

A standard Large Language Model (LLM) at 7 Billion parameters (e.g., Llama-3-8B) serialized in 16-bit precision (`fp16`) requires ~16GB of VRAM strictly for weights, excluding the KV cache. This strictly violates the fractional boundary.

---

## 2. Quantization Overview

Quantization mathematically compresses tensor precision from 16-bit floating point down to 8-bit or 4-bit integers.

| **Format** | **Bit-Depth** | **7B Model Size** | **Performance Impact** | **Target Engine** |
|------------|---------------|-------------------|------------------------|-------------------|
| **FP16**   | 16-bit        | ~14 GB            | Baseline               | PyTorch Native    |
| **INT8**   | 8-bit         | ~7.5 GB           | Minimal                | vLLM / bitsandbytes|
| **AWQ / GPTQ** | 4-bit     | **~3.5 GB**       | Negligible             | vLLM / TensorRT-LLM|
| **GGUF**   | 4-bit / 2-bit | ~3.5 GB           | CPU/GPU Hybrid         | llama.cpp         |

**Conclusion:** 4-bit AWQ or GPTQ quantization is mandatory to execute generative inference within a 3.2GB Time-Slice.

---

## 3. Serving 4-Bit Models via vLLM

vLLM provides native, zero-configuration support for executing AWQ and GPTQ serialized models directly on the GPU.

### Implementation

Instead of downloading base models, configure your deployment manifolds to target pre-quantized artifacts from the HuggingFace registry (e.g., repositories suffixed with `-AWQ`).

```yaml
# manifests/workloads/llm-service.yaml (Excerpt)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llm-inference-worker
spec:
  containers:
  - name: vllm-server
    image: vllm/vllm-openai:latest
    command:
    - "python3"
    - "-m"
    - "vllm.entrypoints.openai.api_server"
    - "--model"
    - "TheBloke/Llama-2-7B-Chat-AWQ"  # Pre-quantized 4-bit model
    - "--quantization"
    - "awq"                           # Explicit quantization flag
    - "--max-model-len"
    - "2048"                          # Constrain KV Cache growth
    - "--gpu-memory-utilization"
    - "0.8"                           # Respect Time-Slicing constraints
```

---

## 4. Calibration & Quality Verification

Quantization introduces minimal perplexity degradation. However, it is mathematically lossy.

**Validation Protocol:**
1. Evaluate the quantized output against the baseline FP16 model using a framework like `lm-evaluation-harness`.
2. Monitor VRAM telemetry in Grafana. If OOMs persist with 4-bit weights, reduce the `--max-model-len` parameter to artificially truncate the maximum token context window, thereby compressing the KV cache footprint.

---

## Next Steps

Proceed to `24-log-aggregation-loki.md` to deploy centralized workload logging.
