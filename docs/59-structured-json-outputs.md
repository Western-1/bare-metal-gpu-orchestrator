# Structured JSON Outputs (Outlines / Guidance)

**Component:** LLM Output Formatting  
**Objective:** Guarantee deterministic, machine-readable JSON schemas from probabilistic models  
**Architecture:** Outlines Integration with vLLM  

---

## 1. The Probabilistic Parsing Problem

Large Language Models are probabilistic text generators. When building enterprise microservices (e.g., an agent that extracts user information from a PDF and saves it to a PostgreSQL database), the application requires strict, machine-readable JSON.

Standard prompting (`"You must return ONLY valid JSON without markdown formatting"`) is notoriously unreliable. The model may occasionally output:
```json
Here is the JSON you requested:
{
  "name": "John Doe"
}
```
This breaks standard `json.loads()` parsers, causing catastrophic pipeline failures and unhandled exceptions in the downstream microservices.

---

## 2. Guided Generation Architecture

To guarantee valid JSON, the architecture must enforce constraints at the **inference engine level** (during token generation), not via prompt engineering.

Frameworks like **Outlines** or **Guidance** integrate directly with vLLM's sampling process. They construct a Finite State Machine (FSM) or Regular Expression (Regex) mask based on a provided JSON Schema (Pydantic model). 
At every generation step, the engine physically prevents the LLM from selecting any token that would violate the schema (e.g., if the schema expects an integer, the engine masks all alphabetical tokens from the probability distribution).

---

## 3. Implementation (vLLM + Outlines)

Recent versions of vLLM have integrated Outlines natively, allowing you to enforce JSON schemas directly via the OpenAI-compatible API.

### 3.1 Define the Pydantic Schema

The developer defines the strict data structure using Python's Pydantic library.

```python
from pydantic import BaseModel, Field

class UserProfile(BaseModel):
    first_name: str = Field(description="The user's first name")
    age: int = Field(description="The user's age in years")
    is_active: bool
```

### 3.2 Querying the Engine

Pass the schema to the vLLM endpoint using the `guided_json` parameter. The vLLM C++ backend will compile the Pydantic model into a regex mask before generation begins.

```python
import json
import openai
from pydantic import TypeAdapter

client = openai.OpenAI(
    api_key="dummy",
    base_url="http://vllm-service.ml-workloads.svc.cluster.local:8000/v1"
)

# Convert Pydantic schema to JSON Schema dictionary
schema_dict = TypeAdapter(UserProfile).json_schema()

response = client.chat.completions.create(
    model="meta-llama/Meta-Llama-3-8B-Instruct",
    messages=[
        {"role": "user", "content": "Extract the data: John is twenty five years old and currently active."}
    ],
    # Enforce token masking at the vLLM engine level
    extra_body={"guided_json": schema_dict}
)

# Guaranteed to be 100% valid JSON matching the Pydantic schema
raw_output = response.choices[0].message.content
user_data = UserProfile.parse_raw(raw_output)

print(user_data.age) # Outputs: 25 (integer)
```

---

## 4. Performance Implications

Compiling the Finite State Machine introduces a slight latency overhead (~50ms) on the first request for a specific schema. However, vLLM caches the compiled FSM in memory, meaning subsequent requests utilizing the same JSON schema incur zero performance penalty while guaranteeing 100% parseable outputs.

---

## Next Steps

Proceed to `60-stateful-ai-agents-langgraph.md` to utilize these structured outputs in long-running, multi-agent autonomous workflows.
