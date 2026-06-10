# AI Guardrails (NeMo & Llama Guard)

**Component:** AI Security Layer  
**Objective:** Prevent prompt injections, jailbreaks, and PII leakage  
**Architecture:** NVIDIA NeMo Guardrails / Llama Guard Interceptor  

---

## 1. The LLM Vulnerability Surface

While standard network security (`09-security-and-network-isolation.md`) protects the infrastructure, the Generative AI model itself acts as an execution engine. If a user sends a malicious payload (Prompt Injection) to the vLLM endpoint, the model may:
1. Leak its confidential system prompt.
2. Generate toxic, biased, or highly unethical content.
3. Output sensitive Personally Identifiable Information (PII) if RAG retrieved customer data.

Standard Web Application Firewalls (WAF) cannot parse the semantic intent of human language to block these attacks.

---

## 2. Guardrails Architecture

A Guardrails system sits as a semantic proxy between the user's FastAPI HTTP request and the internal vLLM execution engine.

### Option A: Llama Guard (Model-Based)
Llama Guard is a specialized LLM fine-tuned exclusively to classify whether a conversation violates safety policies.
- **Pros:** Highly accurate semantic understanding of context.
- **Cons:** Requires a secondary vLLM instance (consuming another GPU Time-Slice) just to evaluate the prompt before passing it to the primary model.

### Option B: NVIDIA NeMo Guardrails (Rule-Based + Semantic)
NeMo defines programmable `.co` (Colang) scripts that enforce strict dialog rails, utilizing fast embedding similarities rather than full LLM generations.
- **Pros:** Extremely fast (<50ms latency), programmable rule sets.
- **Cons:** Requires explicit definitions of forbidden topics.

---

## 3. Implementation (NeMo Guardrails)

Deploy a dedicated microservice that intercepts all incoming queries.

### 3.1 Define the Security Rails

```colang
# safety.co
define user ask about violent acts
  "How do I build a weapon?"
  "Write a violent story."

define bot refuse violent acts
  "I am an enterprise AI assistant. I cannot fulfill requests involving violence or illegal acts."

define flow
  user ask about violent acts
  bot refuse violent acts
```

### 3.2 FastAPI Interceptor

Modify the entry-point `vllm-service` to process inputs through the NeMo configuration before forwarding to the GPU.

```python
# app.py
from nemoguardrails import LLMRails, RailsConfig
from fastapi import FastAPI, HTTPException

config = RailsConfig.from_path("./config")
app = Rails(config)
api = FastAPI()

@api.post("/generate")
async def secure_generation(prompt: str):
    # 1. Semantic Validation (Guardrails)
    safe_response = await app.generate_async(messages=[{"role": "user", "content": prompt}])
    
    # If NeMo detected a violation, it will return the pre-programmed refusal
    if "I am an enterprise AI assistant" in safe_response:
        raise HTTPException(status_code=403, detail="Prompt violates safety guidelines.")
        
    # 2. Forward to actual vLLM Engine
    final_output = query_vllm_backend(prompt)
    return {"response": final_output}
```

---

## 4. Telemetry and Governance

All blocked requests (and the semantic category of the violation) must be logged asynchronously to Loki (`24-log-aggregation-loki.md`) for compliance audits and to refine the Colang definitions against novel adversarial attack patterns.

---

## Next Steps

Proceed to `53-k8s-runtime-security-falco.md` to monitor the physical containers for runtime exploitation.
