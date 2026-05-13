import torch
from fastapi import FastAPI, File, UploadFile, HTTPException
from PIL import Image
from torchvision.models import resnet18, ResNet18_Weights


def configure_gpu_memory(
    device_id: int = 0, memory_fraction: float = 0.20, enable_tf32: bool = True
) -> torch.device:
    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is not available.")

    device = torch.device(f"cuda:{device_id}")
    torch.cuda.set_device(device)
    torch.cuda.set_per_process_memory_fraction(
        fraction=memory_fraction, device=device_id
    )

    if enable_tf32:
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True

    torch.cuda.memory._record_memory_history(False)
    return device


def warmup_model(
    model: torch.nn.Module, device: torch.device, input_shape: tuple
) -> None:
    model.eval()
    with torch.no_grad():
        dummy_input = torch.randn(*input_shape).to(device)
        _ = model(dummy_input)


def get_memory_stats(device: torch.device) -> dict:
    allocated = torch.cuda.memory_allocated(device) / (1024**3)
    reserved = torch.cuda.memory_reserved(device) / (1024**3)
    total = torch.cuda.get_device_properties(device).total_memory / (1024**3)
    return {
        "allocated_gb": allocated,
        "reserved_gb": reserved,
        "total_gb": total,
        "utilization_percent": (allocated / total) * 100,
    }


app = FastAPI(title="Vision API")

# Configure GPU memory
device = configure_gpu_memory(device_id=0, memory_fraction=0.20)

# Load pretrained ResNet-18
weights = ResNet18_Weights.DEFAULT
model = resnet18(weights=weights)
model = model.to(device)
model.eval()

# Image preprocessing
preprocess = weights.transforms()

# Warmup model
warmup_model(model, device, input_shape=(1, 3, 224, 224))


@app.post("/classify")
async def classify(file: UploadFile = File(...)):
    """Classify uploaded image."""
    try:
        image = Image.open(file.file).convert("RGB")
        image_tensor = preprocess(image).unsqueeze(0).to(device)

        stats_before = get_memory_stats(device)

        with torch.no_grad():
            prediction = model(image_tensor)

        stats_after = get_memory_stats(device)

        category_id = prediction.argmax().item()
        category_name = weights.meta["categories"][category_id]

        return {
            "category": category_name,
            "confidence": float(prediction.softmax(dim=1)[0][category_id]),
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

    uvicorn.run(app, host="0.0.0.0", port=8001)
