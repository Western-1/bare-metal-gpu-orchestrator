# Dynamic Batching with vLLM (Enterprise Optimization)

While standard PyTorch/HuggingFace implementations process requests sequentially, an Enterprise MLOps environment must use **Dynamic Batching** to handle concurrent load.

## The Problem
If 10 users send 10 prompts at the exact same millisecond, a standard FastAPI backend will process them one-by-one or attempt to run all 10 simultaneously, resulting in a CUDA Out-of-Memory (OOM) error.

## The Solution: vLLM
vLLM is a high-throughput and memory-efficient LLM serving engine.

**Key Features:**
1. **PagedAttention**: Manages attention keys and values (KV cache) like an operating system manages virtual memory. It partitions the KV cache into blocks, eliminating memory fragmentation and allowing sharing of KV cache across requests.
2. **Continuous Batching**: Dynamically groups incoming requests into a single batch, processes them together on the GPU, and un-batches the results, increasing throughput by up to 20x compared to naive HuggingFace implementations.

## Migration Path
To migrate `embedding-service` or a text generation service to vLLM:
1. Add `vllm` to `requirements.txt`.
2. Replace `SentenceTransformer` or `AutoModelForCausalLM` with `vllm.LLM` and `vllm.AsyncEngine`.
3. Start the server using vLLM's optimized OpenAI-compatible API endpoints.
