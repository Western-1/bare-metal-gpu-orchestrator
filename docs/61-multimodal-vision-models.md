# Multimodal Vision Models (LLaVA / CLIP)

**Component:** Vision Inference (Coutury Core)  
**Objective:** Optimize serving of heavy image-based models on constrained VRAM  
**Architecture:** Triton Inference Server + vLLM (Multimodal) + S3 Object Storage  

---

## 1. The Coutury Vision Bottleneck

For a fashion-tech startup like Coutury, textual LLMs are secondary. The core product relies on **Computer Vision**: users uploading photos of their clothes, the system segmenting items (pants, shirts), generating embeddings for vector search, and composing new outfits (Generative AI).

Images are computationally catastrophic compared to text. 
- A text prompt of 500 words might consume a few kilobytes of VRAM.
- A single 1080p image tensor, uncompressed into VRAM for a ResNet or LLaVA forward pass, consumes hundreds of megabytes. 

If 10 users upload outfit photos simultaneously, a naïve FastAPI implementation will instantly trigger a CUDA Out-Of-Memory (OOM) error, crashing the single RTX 5070 Ti.

---

## 2. Multimodal Inference Architecture

To survive image-heavy traffic on a single GPU, the architecture must aggressively decouple data transit from GPU execution.

### 2.1 The Payload Anti-Pattern (Base64)
**Do NOT** send Base64 encoded images directly in the JSON payload to the FastAPI/vLLM backend. 
Parsing 5MB Base64 strings blocks the Python Event Loop, and decoding it in system RAM before passing to the GPU creates massive CPU/Memory spikes.

### 2.2 The Presigned URL Pattern
1. The Mobile App requests an AWS S3 (MinIO) Presigned Upload URL from the backend.
2. The Mobile App uploads the JPEG directly to MinIO (Bypassing the API/GPU entirely).
3. The Mobile App sends only the `image_url` to the ML Backend.
4. The ML Worker uses PyTorch with GPUDirect Storage (`49-gpu-direct-storage.md`) to stream the tensor directly into VRAM for inference.

---

## 3. Triton & vLLM Multimodal Setup

### 3.1 Serving LLaVA (Large Language-and-Vision Assistant)

vLLM supports multimodal models natively. It allocates a dedicated VRAM chunk for the vision encoder.

```bash
# Launch vLLM with LLaVA support
python3 -m vllm.entrypoints.openai.api_server \
    --model llava-hf/llava-1.5-7b-hf \
    --chat-template template_llava.jinja \
    --image-input-type pixel_values \
    --max-model-len 4096 \
    --gpu-memory-utilization 0.6 # Strict limit for Time-Slicing
```

### 3.2 Dynamic Batching for Images (Triton)

For pure vision tasks (e.g., YOLO segmentation for isolating a jacket from a photo), **Triton Inference Server** is superior. Triton dynamically waits a few milliseconds to accumulate multiple images from different HTTP requests into a single tensor batch (e.g., `Batch Size: 4`) before executing the GPU kernel. 
This increases throughput by 300% compared to processing 4 images sequentially.

---

## 4. Coutury Inference Pipeline

The optimal flow for an "Outfit Generation" request:
1. **API Gateway:** Receives the user request + MinIO Object ID.
2. **Segmentation (Triton):** A lightweight YOLOv8 model extracts the "shirt" from the image.
3. **Embedding (Triton):** A CLIP model converts the cropped shirt into a vector embedding.
4. **Vector Search (Qdrant):** Finds 5 matching pants from the Coutury database.
5. **Generative Composition (vLLM):** A multimodal model (or Diffusion model) generates the final composite image of the outfit.

All steps execute in distinct GPU Time-Slices, isolated by strict VRAM limits.
