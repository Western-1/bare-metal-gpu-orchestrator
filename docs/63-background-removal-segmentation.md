# Background Removal & Segmentation

**Component:** Image Preprocessing Pipeline (Coutury Core)  
**Objective:** Isolate clothing items to ensure high-fidelity embeddings  
**Architecture:** Triton Server + U^2-Net / YOLOv8-seg  

---

## 1. The Fashion AI Preprocessing Problem

When a user uploads a photo of an outfit to Coutury, they typically submit a mirror selfie. The image contains not just the clothing, but also the user's face, the bedroom background, lighting artifacts, and multiple distinct garments (e.g., a jacket over a shirt).

If this raw image is fed directly into a CLIP embedding model (`64-visual-search-clip-qdrant.md`), the generated vector mathematically encodes the entire scene. A search for "similar items" will prioritize photos with identical bedroom backgrounds or lighting, rather than matching the actual jacket.

**Rule:** AI models must only "see" the isolated pixels of the target garment.

---

## 2. The Multi-Stage Cropping Pipeline

Before any Generative AI or Vector Search occurs, the image must pass through a strict segmentation pipeline.

### Step 1: Detection (YOLOv8)
A lightweight object detection model (e.g., YOLOv8 trained on DeepFashion) identifies the bounding boxes of distinct items.
- *Input:* 1 Raw Image
- *Output:* Bounding Box A (Shirt), Bounding Box B (Pants)

### Step 2: Background Removal (U^2-Net / rembg)
The cropped bounding boxes are passed to a salient object detection model (like `rembg` powered by U^2-Net).
- *Input:* Bounding box containing the shirt and background pixels.
- *Output:* An RGBA image where all background pixels are strictly transparent (`alpha=0`), or replaced with a pure white background (`#FFFFFF`).

---

## 3. Triton Inference Server Deployment

Running segmentation directly in the FastAPI Python event loop is highly inefficient. Background removal models are perfect candidates for the **Triton Inference Server** (`33-triton-inference-server.md`).

Triton allows us to host the ONNX-compiled `U^2-Net` model in a dedicated GPU Time-Slice, dynamically batching incoming user uploads.

### 3.1 Model Repository Structure
```text
/models
  /rembg
    config.pbtxt
    /1
      model.onnx
```

### 3.2 config.pbtxt (Triton Configuration)
```protobuf
name: "rembg"
platform: "onnxruntime_onnx"
max_batch_size: 8
input [
  {
    name: "input"
    data_type: TYPE_FP32
    dims: [ 3, 320, 320 ]
  }
]
output [
  {
    name: "output"
    data_type: TYPE_FP32
    dims: [ 1, 320, 320 ]
  }
]
instance_group [
  {
    count: 1
    kind: KIND_GPU
  }
]
```

---

## 4. Coutury FastAPI Integration

The backend orchestrates this flow asynchronously to maintain low latency.

```python
import httpx
import numpy as np

async def preprocess_outfit(raw_image_bytes):
    # 1. Resize and normalize image for U^2-Net
    tensor = preprocess_for_onnx(raw_image_bytes)
    
    # 2. Call Triton Server via gRPC/HTTP
    async with httpx.AsyncClient() as client:
        triton_response = await client.post(
            "http://triton.ml-workloads.svc.cluster.local:8000/v2/models/rembg/infer",
            json={"inputs": [{"name": "input", "datatype": "FP32", "shape": [1, 3, 320, 320], "data": tensor.tolist()}]}
        )
    
    # 3. Apply the generated alpha mask to the original image
    mask = np.array(triton_response.json()["outputs"][0]["data"])
    clean_garment = apply_mask(raw_image_bytes, mask)
    
    return clean_garment
```

---

## Next Steps

With the background cleanly removed, proceed to `64-visual-search-clip-qdrant.md` to generate the vector embeddings for visual similarity search.
