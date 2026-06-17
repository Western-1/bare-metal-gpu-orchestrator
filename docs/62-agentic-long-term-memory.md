# Agentic Long-Term Memory (Mem0)

**Component:** AI Personalization (Coutury V2.0)  
**Objective:** Maintain cross-session semantic memory of user preferences  
**Architecture:** Mem0 + Qdrant (Vector DB) + PostgreSQL  

---

> [!NOTE] 
> **V2.0 Roadmap:** This architecture is designed for the Post-MVP phase. Initial MVP versions will rely on standard session context (LangGraph/Redis). This document outlines the pathway to hyper-personalization.

---

## 1. The Personalization Problem

In an AI stylist app like Coutury, users expect the system to learn their tastes over time. 
If a user explicitly states in March, *"I don't like skinny jeans, I prefer wide-leg,"* and in May asks, *"Generate a summer outfit for me,"* the LLM will hallucinate skinny jeans because the March conversation is no longer in the context window.

Standard RAG (`34-rag-vector-database-qdrant.md`) retrieves product catalogs, but it is not optimized for dynamically extracting and storing evolving human preferences.

---

## 2. Mem0 Architecture

**Mem0** is a semantic memory layer designed specifically for AI agents. It does not just store raw chat logs; it actively uses a lightweight LLM in the background to **extract facts** from conversations and consolidate them into a user profile.

1. **Fact Extraction:** User says "I hate skinny jeans". Mem0 extracts: `{"entity": "user", "preference": "dislikes skinny jeans", "category": "style"}`.
2. **Vector Storage:** This fact is embedded and stored in Qdrant, keyed to the `user_id`.
3. **Context Injection:** When the user asks for a summer outfit, Mem0 intercepts the prompt, queries Qdrant for all style preferences for `user_id`, and injects: *"Remember: The user dislikes skinny jeans."* into the system prompt.

---

## 3. Implementation Pathway (V2)

Deploy Mem0 as a microservice running alongside the AI Gateway (`57-ai-api-gateway-litellm.md`).

### 3.1 Adding Memories Asynchronously

To avoid slowing down the user's chat response, memory extraction runs in a Celery background worker (`20-keda-autoscaling.md`).

```python
from mem0 import Memory

# Connect Mem0 to our existing Qdrant deployment
config = {
    "vector_store": {
        "provider": "qdrant",
        "config": {
            "host": "qdrant.data-plane.svc.cluster.local",
            "port": 6333,
        }
    }
}
m = Memory.from_config(config)

def background_extract_memory(user_id: str, chat_message: str):
    # Mem0 uses an LLM to decide if the message contains a permanent preference
    m.add(chat_message, user_id=user_id)
```

### 3.2 Retrieving Memories at Inference

At inference time, query Mem0 before hitting the vLLM engine.

```python
@app.post("/generate_outfit")
async def generate_outfit(user_id: str, prompt: str):
    # 1. Fetch user's long-term style preferences
    user_memories = m.search(prompt, user_id=user_id)
    
    # Format memories into a string
    memory_context = "\n".join([mem["text"] for mem in user_memories])
    
    # 2. Construct hyper-personalized prompt
    system_prompt = f"""You are Coutury, a professional stylist. 
    Design an outfit based on the user's request.
    
    USER PREFERENCES YOU MUST FOLLOW:
    {memory_context}
    """
    
    # 3. Generate outfit via vLLM
    return call_vllm(system_prompt, prompt)
```

---

## 4. Conflict Resolution

Mem0 handles evolving tastes. If the user later says, *"Actually, skinny jeans are back in style for me,"* Mem0 automatically updates or invalidates the older memory vector, ensuring the stylist agent always acts on the most recent truth.
