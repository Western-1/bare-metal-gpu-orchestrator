# AI API Gateway (LiteLLM)

**Component:** LLM Routing & Cost Control  
**Objective:** Unified API interface, model fallback, and tenant budget enforcement  
**Architecture:** LiteLLM + PostgreSQL Backend  

---

## 1. The Multi-Model Routing Problem

As an organization matures, it never relies on a single model. 
- Internal RAG pipelines might use a local Llama-3 (via vLLM) on the bare-metal GPU cluster (`15-dynamic-batching-vllm.md`) to ensure data privacy.
- Marketing teams might require the reasoning capabilities of OpenAI's GPT-4o via public API.
- If the local bare-metal cluster experiences an outage (or queue saturation), internal requests must failover to a commercial API automatically to prevent downtime.

Hardcoding distinct API keys and endpoint URLs into dozens of downstream microservices creates a security and operational nightmare.

---

## 2. LiteLLM Architecture

**LiteLLM** acts as an AI API Gateway. It exposes a single, OpenAI-compatible API endpoint to all internal developers, abstracting away the complexity of the underlying model providers.

### Capabilities:
1. **Universal API:** Translates OpenAI-formatted requests into Anthropic, Gemini, or local vLLM formats dynamically.
2. **Fallback & Retries:** If the local vLLM cluster returns HTTP 429 (Too Many Requests), LiteLLM automatically retries the query against an Azure OpenAI endpoint.
3. **Cost Tracking & Budgets:** Tracks every token generated and enforces monthly dollar budgets per internal team (Namespace) via virtual API keys.

---

## 3. Deployment Configuration

LiteLLM requires a relational database (PostgreSQL) to store virtual keys, budgets, and routing rules.

### 3.1 Helm Deployment

```bash
# Add the LiteLLM Helm chart
helm repo add litellm https://litellm.github.io/litellm
helm repo update

# Deploy with PostgreSQL enabled
helm install litellm litellm/litellm \
  --namespace ai-gateway \
  --create-namespace \
  --set postgres.enabled=true \
  --set master_key="sk-enterprise-master-key"
```

### 3.2 Routing & Fallback Configuration

Configure the LiteLLM proxy via `config.yaml` to define the routing logic.

```yaml
# litellm-config.yaml
model_list:
  # Primary: Local Bare-Metal vLLM Cluster
  - model_name: enterprise-model
    litellm_params:
      model: openai/Llama-3-8B-Instruct
      api_base: http://vllm-service.ml-workloads.svc.cluster.local:8000/v1
      api_key: "dummy-key"
      
  # Fallback: Commercial API
  - model_name: enterprise-model-fallback
    litellm_params:
      model: gpt-4o-mini
      api_key: "os.environ/OPENAI_API_KEY"

router_settings:
  routing_strategy: usage-based-routing
  fallbacks: [{"enterprise-model": ["enterprise-model-fallback"]}]
```

### 3.3 Internal Consumption

Developers no longer connect to vLLM or OpenAI directly. They point their SDKs exclusively to the cluster's internal LiteLLM service.

```python
import openai

client = openai.OpenAI(
    api_key="sk-virtual-team-alpha-key",
    base_url="http://litellm.ai-gateway.svc.cluster.local:4000/v1"
)

# LiteLLM routes this to the local vLLM cluster, or falls back to OpenAI if vLLM is down
response = client.chat.completions.create(
    model="enterprise-model",
    messages=[{"role": "user", "content": "Analyze this data."}]
)
```

---

## Next Steps

Proceed to `58-semantic-caching-redis.md` to deploy GPTCache within the routing layer to save GPU VRAM on repetitive queries.
