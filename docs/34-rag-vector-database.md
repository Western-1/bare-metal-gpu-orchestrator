# Retrieval-Augmented Generation (RAG) Architecture

**Component:** Vector Database (Milvus/Qdrant)  
**Objective:** Scale and query high-dimensional embeddings  
**Integration:** Downstream from `embedding-service`  

---

## 1. Architectural Need

The `embedding-service` deployed earlier generates high-dimensional float arrays (e.g., 768-D vectors) representing text semantics. For these embeddings to be actionable in a Retrieval-Augmented Generation (RAG) pipeline with an LLM, they must be indexed, persisted, and queried using Approximate Nearest Neighbor (ANN) algorithms (like HNSW).

Standard relational databases (PostgreSQL) scale poorly for billion-scale vector similarity search.

---

## 2. Vector Database Deployment

This architecture recommends **Milvus** (for massive multi-node scale) or **Qdrant** (for single-node/lightweight deployments) as the stateful vector persistence layer.

### Qdrant Deployment via Helm

Qdrant is written in Rust and integrates seamlessly into the k3s environment with minimal CPU overhead.

```bash
helm repo add qdrant https://qdrant.github.io/qdrant-helm
helm repo update

# Deploy Qdrant in Distributed Mode
helm install qdrant qdrant/qdrant \
  --namespace data-plane \
  --set replicaCount=3 \
  --set persistence.storageClassName=rook-cephfs \
  --set persistence.size=100Gi
```

---

## 3. RAG Pipeline Integration

### 3.1 Data Ingestion

The Celery `background-worker` processes documents asynchronously, invoking the local Time-Sliced `embedding-service`, and bulk-inserts the generated vectors into Qdrant.

```python
# Ingestion Flow (Pseudo-code)
def process_document(text_chunk):
    # 1. Generate Vector (Internal HTTP Call to Embedding Pod)
    vector = requests.post("http://embedding-service/encode", json={"text": text_chunk}).json()
    
    # 2. Insert into Vector DB
    qdrant_client.upsert(
        collection_name="enterprise_knowledge",
        points=[{"id": uuid.uuid4(), "vector": vector, "payload": {"text": text_chunk}}]
    )
```

### 3.2 Retrieval and Generation

The client-facing RAG API executes the synchronous retrieval query.

```python
# Retrieval Flow (Pseudo-code)
def query_rag(user_prompt):
    # 1. Embed the prompt
    query_vector = embed_text(user_prompt)
    
    # 2. Similarity Search (HNSW)
    hits = qdrant_client.search(collection_name="enterprise_knowledge", query_vector=query_vector, limit=5)
    context = "\n".join([hit.payload["text"] for hit in hits])
    
    # 3. LLM Generation via vLLM
    augmented_prompt = f"Context: {context}\n\nQuestion: {user_prompt}"
    response = requests.post("http://vllm-service/generate", json={"prompt": augmented_prompt})
    return response
```

---

## Next Steps

Proceed to `35-secrets-management-vault.md` to secure the vector database API keys.
