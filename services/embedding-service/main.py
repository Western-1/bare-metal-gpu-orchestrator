import os
import asyncio
import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer


def configure_gpu_memory(
    device_id: int = 0, memory_fraction: float = 0.20, enable_tf32: bool = True
) -> torch.device:
    """
    Configure PyTorch GPU memory settings for Time-Sliced environments.
    """
    if not torch.cuda.is_available():
        raise RuntimeError(
            "CUDA is not available. Check GPU driver and container runtime."
        )

    device = torch.device(f"cuda:{device_id}")
    torch.cuda.set_device(device)

    # Critical: Set memory fraction to limit VRAM usage and prevent OOMs
    torch.cuda.set_per_process_memory_fraction(
        fraction=memory_fraction, device=device_id
    )

    if enable_tf32:
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True

    torch.cuda.memory._record_memory_history(False)
    return device


def warmup_model(model, device: torch.device, input_shape: tuple) -> None:
    """Perform a warmup forward pass to pre-allocate VRAM."""
    model.eval()
    with torch.no_grad():
        # SentenceTransformer expects text input for encoding
        _ = model.encode("warmup text", convert_to_tensor=True)


def get_memory_stats(device: torch.device) -> dict:
    """Get current GPU memory statistics."""
    allocated = torch.cuda.memory_allocated(device) / (1024**3)
    reserved = torch.cuda.memory_reserved(device) / (1024**3)
    total = torch.cuda.get_device_properties(device).total_memory / (1024**3)

    return {
        "allocated_gb": allocated,
        "reserved_gb": reserved,
        "total_gb": total,
        "utilization_percent": (allocated / total) * 100,
    }


app = FastAPI(title="Embedding API")

# Setup concurrency limit (Semaphore) to prevent OOM
MAX_CONCURRENT_REQUESTS = int(os.getenv("MAX_CONCURRENT_REQUESTS", 4))
semaphore = asyncio.Semaphore(MAX_CONCURRENT_REQUESTS)

# Configure GPU memory on startup
device = configure_gpu_memory(device_id=0, memory_fraction=0.20)

# Load model
model = SentenceTransformer("all-MiniLM-L6-v2")
model = model.to(device)

# Warmup model to pre-allocate VRAM
warmup_model(model, device, input_shape=(1, 512))


class EmbeddingRequest(BaseModel):
    text: str


@app.post("/embed")
async def embed(request: EmbeddingRequest):
    """Generate text embeddings."""
    try:
        stats_before = get_memory_stats(device)

        # The semaphore blocks execution here if more than 4 requests are running,
        # forcing excess requests to wait in RAM rather than crashing the GPU.
        async with semaphore:
            with torch.no_grad():
                embedding = model.encode(request.text, convert_to_tensor=True)

        stats_after = get_memory_stats(device)

        return {
            "embedding": embedding.cpu().tolist(),
            "memory_stats": {"before": stats_before, "after": stats_after},
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
async def health():
    """Health check endpoint."""
    stats = get_memory_stats(device)
    return {"status": "healthy", "memory_stats": stats}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
