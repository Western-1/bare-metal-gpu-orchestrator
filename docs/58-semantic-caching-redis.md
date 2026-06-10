# Semantic Caching (GPTCache & Redis)

**Component:** Inference Optimization  
**Objective:** Bypass GPU computation for semantically identical queries  
**Architecture:** GPTCache + Redis (Vector Similarity)  

---

## 1. The Redundant Compute Problem

Generative AI inference is extremely expensive in terms of VRAM and Watt-Hours (`45-energy-attribution-kepler.md`). 

In a customer support application, 30% of incoming queries are often semantic duplicates. 
- *User A:* "How do I reset my password?"
- *User B:* "I forgot my password, what do I do?"
- *User C:* "Help me change my password."

Standard HTTP caches (e.g., Nginx, Varnish) fail because the raw text strings are different. Consequently, the vLLM engine performs a full, expensive forward pass on the GPU for every query, generating essentially the same response and unnecessarily congesting the Time-Sliced GPU queue.

---

## 2. Semantic Caching Architecture

**Semantic Caching** solves this by caching responses based on the mathematical meaning (embeddings) of the prompt, rather than strict string matching.

1. **Embed:** The user's prompt is quickly converted into a lightweight vector using the local `embedding-service`.
2. **Search:** The system queries a Vector Database (or Redis with RediSearch) to find if a highly similar vector (e.g., >95% cosine similarity) already exists in the cache.
3. **Hit:** If a match is found, the cached LLM response is returned instantly (Sub-5ms). The GPU is bypassed entirely.
4. **Miss:** If no match is found, the prompt is forwarded to the vLLM engine, and the resulting answer is stored in the cache for future use.

---

## 3. Implementation (GPTCache)

GPTCache is deployed as middleware within the API Gateway (`57-ai-api-gateway-litellm.md`) or the FastAPI application layer.

### 3.1 Dependencies

Deploy a Redis instance with the RediSearch module enabled (standard Redis cannot perform vector similarity search).

```bash
helm install redis-cache oci://registry-1.docker.io/bitnamicharts/redis \
  --set image.repository=redis/redis-stack-server \
  --namespace data-plane
```

### 3.2 Python Integration

Integrate GPTCache into the FastAPI endpoint.

```python
import os
from gptcache import cache
from gptcache.embedding import Onnx
from gptcache.manager import CacheBase, VectorBase, get_data_manager
from gptcache.similarity_evaluation.distance import SearchDistanceEvaluation

# 1. Initialize local lightweight embedding model (runs on CPU)
onnx = Onnx()

# 2. Connect to Redis Vector Store
redis_cache = CacheBase('redis', host='redis-cache.data-plane.svc.cluster.local', port=6379)
vector_base = VectorBase('redis', host='redis-cache.data-plane.svc.cluster.local', port=6379, dimension=onnx.dimension)
data_manager = get_data_manager(cache_base=redis_cache, vector_base=vector_base)

# 3. Configure the Semantic Cache threshold
cache.init(
    embedding_func=onnx.to_embeddings,
    data_manager=data_manager,
    similarity_evaluation=SearchDistanceEvaluation(),
    similarity_threshold=0.92  # 92% semantic match required for a cache HIT
)

@app.post("/chat")
async def chat_endpoint(prompt: str):
    # This call is intercepted by GPTCache
    # If the prompt is similar to a previous one, vLLM is bypassed
    response = await query_vllm_with_cache(prompt)
    return {"response": response}
```

---

## 4. Cache Invalidation Strategy

Semantic caching introduces the risk of serving stale information if the underlying knowledge base (RAG) is updated.

Configure a TTL (Time-To-Live) on the Redis keys (e.g., 24 hours), or implement a webhook that flushes the Redis cache whenever the `46-data-version-control-dvc.md` pipeline triggers a data update.

---

## Next Steps

Proceed to `59-structured-json-outputs.md` to ensure uncached queries return perfectly formatted data structures.
