# Stateful AI Agents (LangGraph)

**Component:** Agentic Workflows  
**Objective:** Orchestrate long-running, stateful, multi-agent AI systems  
**Architecture:** LangGraph + PostgreSQL Checkpointer + KEDA  

---

## 1. The Limitation of Stateless LLM Chains

Traditional LLM applications (like Retrieval-Augmented Generation / RAG) are stateless. A request comes in, context is retrieved, a prompt is generated, and a response is returned. 

However, modern **Agentic AI** requires models to execute loops, use external tools (e.g., bash terminals, web scrapers), evaluate their own work, and correct mistakes over minutes or hours. 

If a pod crashes during a 20-minute agentic code-generation loop, the entire state is lost. Furthermore, complex tasks require **Human-in-the-Loop (HITL)** approval (e.g., an agent proposes a database migration, but waits for human authorization before executing it).

---

## 2. LangGraph Architecture

**LangGraph** models agent workflows as state machines (graphs). Nodes represent agents or tools, and edges represent the control flow logic.

Crucially, LangGraph incorporates a **Checkpointer**. After every step in the graph, the entire state of the agent (memory, variables, history) is serialized and persisted to a PostgreSQL database.

This enables:
1. **Resilience:** If the Kubernetes Pod dies, a new Pod can resume the agent exactly where it left off.
2. **Time Travel:** Developers can rewind an agent's state to a previous node, alter the prompt, and fork the execution.
3. **Interrupts:** The graph can pause execution, serialize state, and wait asynchronously for an external API call (human approval) to resume.

---

## 3. Implementation Workflow

### 3.1 PostgreSQL Checkpointer Setup

Ensure a highly available PostgreSQL database (`37-ha-control-plane.md`) is available to store the thread states.

### 3.2 Defining the Agent Graph

```python
# agent_graph.py
from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.postgres import PostgresSaver

# 1. Define the State
class AgentState(TypedDict):
    messages: list
    action_required: bool
    human_approved: bool

# 2. Define Nodes (The AI logic)
def agent_node(state: AgentState):
    # Call vLLM to decide on an action
    response = call_vllm_api(state["messages"])
    return {"messages": [response], "action_required": True}

def execution_node(state: AgentState):
    # Execute the dangerous action (e.g., SQL query)
    execute_sql(state["messages"][-1])
    return {"action_required": False}

# 3. Define the Graph
workflow = StateGraph(AgentState)
workflow.add_node("agent", agent_node)
workflow.add_node("execute", execution_node)

# Conditional edge: Wait for human if action required
workflow.add_conditional_edges(
    "agent",
    lambda x: "execute" if x["human_approved"] else END
)

# 4. Compile with Persistence
DB_URI = "postgresql://user:pass@postgres.data-plane.svc.cluster.local:5432/agents"
checkpointer = PostgresSaver.from_conn_string(DB_URI)

app = workflow.compile(checkpointer=checkpointer, interrupt_before=["execute"])
```

### 3.3 Execution and Human-in-the-Loop

The graph is executed via a FastAPI endpoint. The `thread_id` acts as the persistence key.

```python
# 1. Start the agent (It will pause before the 'execute' node)
config = {"configurable": {"thread_id": "user_session_123"}}
for event in app.stream({"messages": ["Drop the test database"]}, config):
    print(event)

# 2. Human reviews the state via UI, and sends approval via another endpoint
app.update_state(config, {"human_approved": True})

# 3. Resume execution from the checkpoint
for event in app.stream(None, config):
    print(event)
```

---

## 4. Serverless Worker Scaling

Because these agent workflows are long-running and stateful, they should not block synchronous HTTP threads. 
The execution logic is offloaded to Celery/Redis workers. We utilize KEDA (`20-keda-autoscaling.md`) to dynamically scale the agent worker pods based on the volume of active LangGraph threads in the queue.

---

**End of Application Layer Documentation Series.**
