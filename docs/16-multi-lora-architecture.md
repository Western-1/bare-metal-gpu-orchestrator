# Multi-LoRA Serving Architecture

**Component:** LoRA (Low-Rank Adaptation) Multiplexing  
**Objective:** Scale multi-tenant custom models without VRAM exhaustion  
**Supported Engines:** vLLM, LoRAX  

---

## 1. The Multi-Tenancy VRAM Bottleneck

Providing specialized foundation models across heterogeneous client domains (e.g., Medical, Legal, Financial) requires isolated fine-tuning.
Executing full-parameter loading for 50 distinct fine-tunes of a 70B parameter model demands ~2000GB of VRAM (50 clients × 40GB/model), necessitating massive horizontal hardware scaling and incurring prohibitive infrastructure costs.

---

## 2. Low-Rank Adaptation (LoRA) Architecture

LoRA bypasses full-parameter fine-tuning by freezing the foundation model weights and injecting trainable rank decomposition matrices into the transformer architecture. The resulting adapter artifact encapsulates domain-specific delta weights and is highly compact (typically 50MB - 100MB).

### Multiplexing Implementation

1. **Foundation Model Initialization**: Load the quantized base model (e.g., `Llama-3-70B-Instruct-AWQ`) into VRAM a single time.
2. **Adapter Storage**: Persist the LoRA adapter binaries across the HostPath PVC array (see `12-model-caching-pvc.md`).
3. **Dynamic KV Injection**: 
   - Upon ingress request routing (e.g., Tenant ID: `legal-01`), the inference engine (vLLM/LoRAX) loads the targeted adapter delta weights from disk into VRAM.
   - The engine dynamically maps the LoRA tensors into the execution graph for that specific request batch.
   - Adapter weights are swapped in milliseconds with sub-millisecond overhead for sequential cache hits.

---

## 3. Resource Impact Analysis

| **Architecture** | **Base Weights** | **Adapter Weights** | **Total VRAM Demand** |
|------------------|------------------|---------------------|-----------------------|
| **Naive (50 Full Models)** | 50 × 40GB | N/A | **2000 GB** |
| **Multi-LoRA (50 Adapters)** | 1 × 40GB | 50 × 100MB | **~45 GB** |

**Conclusion:** Multi-LoRA topologies consolidate 50+ custom models onto a single physical GPU or Time-Sliced partition, representing the optimal density standard for multi-tenant MLOps.

---

## Next Steps

Proceed to `17-opentelemetry-tracing.md` to configure distributed tracing across the inference pipeline.
