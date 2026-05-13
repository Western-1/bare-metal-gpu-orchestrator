# 19. Concurrency Limits (OOM Protection)

In an environment where a single PyTorch model runs on a constrained VRAM partition (e.g., 3.2 GB in a GPU Time-Slicing scenario), exposing an endpoint to unrestricted HTTP traffic guarantees an Out Of Memory (OOM) crash during traffic spikes. 

While message queues (like Redis) are perfect for background tasks, they add unacceptable latency for synchronous REST APIs where users expect sub-second responses.

To solve this for synchronous APIs, we use **Concurrency Limits via Semaphores**.

---

## How It Works

Instead of letting FastAPI flood the GPU with every incoming request concurrently, we place an `asyncio.Semaphore` immediately before the PyTorch `forward()` or `encode()` execution block.

1. **The Gatekeeper**: The semaphore is initialized with a strict limit (e.g., 4).
2. **Waiting in RAM**: If 50 requests arrive instantly, the first 4 enter the GPU. The remaining 46 are paused by the `async with semaphore:` block. 
3. **Safe Queuing**: The paused requests wait safely in the server's main system RAM (which is abundant) without touching the precious GPU VRAM.
4. **Execution**: As soon as 1 request finishes and exits the `async with` block, the next request is instantly pushed to the GPU.

---

## Configuration

In this project, the concurrency limit is easily configurable via the `MAX_CONCURRENT_REQUESTS` environment variable.

### Modifying Locally (Docker Compose)
Edit the environment block in `docker-compose.yaml`:

```yaml
  embedding-service:
    environment:
      - REDIS_URL=redis://redis:6379/0
      - MAX_CONCURRENT_REQUESTS=8   # Adjust based on memory profiling
```

### Modifying in Kubernetes
For production, adjust the `env` array in your `Deployment` manifests:

```yaml
        env:
        - name: MAX_CONCURRENT_REQUESTS
          value: "16"
```

## Determining the Optimal Limit

The ideal number depends on your batch size, model size, and memory fraction.
To find it:
1. Run a load test (e.g., Locust).
2. Monitor VRAM usage (which is returned in the API response under `memory_stats`).
3. Gradually increase `MAX_CONCURRENT_REQUESTS` until VRAM hits ~80%. This is your maximum safe concurrency.
