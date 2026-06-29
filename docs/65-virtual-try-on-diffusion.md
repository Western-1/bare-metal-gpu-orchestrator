# Virtual Try-On (VTON) via Diffusion

**Component:** Generative AI (Coutury Core)  
**Objective:** Generate hyper-realistic images of users wearing selected garments  
**Architecture:** Stable Diffusion + ControlNet / OOTDiffusion  

---

## 1. The Fashion "Holy Grail"

Finding the perfect garment via Visual Search (`64-visual-search-clip-qdrant.md`) solves half the problem. The ultimate conversion driver in Fashion-Tech is **Virtual Try-On (VTON)**. 

Users want to upload a photo of themselves and see exactly how the retrieved jacket looks on their body type, preserving their pose, facial features, and background, while realistically draping the new fabric.

---

## 2. VTON Architecture

Standard Stable Diffusion (Text-to-Image) cannot solve this because it hallucinates new people. We must constrain the generation process so the AI acts only as a "digital tailor".

### 2.1 The Two-Image Input System
State-of-the-art VTON models (like **OOTDiffusion** or **IDM-VTON**) require two inputs:
1. **Person Image:** The raw photo of the user.
2. **Garment Image:** The cleanly cropped clothing item (`63-background-removal-segmentation.md`).

### 2.2 The Inpainting Mask
To tell the model *where* to generate the new clothes, the pipeline automatically generates a binary mask (e.g., using `DensePose` or `MediaPipe`) over the user's upper body. The model "inpaints" (fills in) this masked area using the textures and style extracted from the Garment Image.

---

## 3. Deployment on Constrained VRAM (RTX 5070 Ti)

Image generation via Diffusion models is notoriously VRAM-heavy. A naive implementation will crash a 16GB GPU immediately, especially if Triton (Vision search) and vLLM are already occupying Time-Slices.

### 3.1 Model Quantization & Optimization (TensorRT)
Do not run raw PyTorch weights in production.
1. Export the Diffusion model to ONNX.
2. Compile it using **NVIDIA TensorRT**. 
TensorRT optimizes the UNet layers for the exact architecture of the RTX 5070 Ti (Ada Lovelace), drastically reducing VRAM usage (often cutting it by 40%) and speeding up inference by 3x.

### 3.2 Asynchronous Queueing (Celery)
VTON takes 3-10 seconds per image. It must **never** block the synchronous HTTP FastAPI threads.

1. The API Gateway receives the user's request and drops it into a Redis Queue.
2. The API immediately returns a `task_id` to the Mobile App (Status: `processing`).
3. A dedicated Celery Worker (running on a specific GPU Time-Slice) pulls the task, executes the TensorRT Diffusion model, and saves the output image to S3 (MinIO).
4. The Mobile App polls the API (or listens via WebSockets) until the S3 URL is ready.

---

## 4. Pipeline Integration

The full end-to-end Coutury flow is now complete:

```python
@celery_app.task(name="generate_vton")
def background_vton_task(user_image_s3, garment_image_s3):
    # 1. Download images from local MinIO
    user_img = download_from_s3(user_image_s3)
    garment_img = download_from_s3(garment_image_s3)
    
    # 2. Generate Human Parsing Mask (Identify torso/arms)
    mask = generate_body_mask(user_img)
    
    # 3. Execute TensorRT Optimized Diffusion Model
    # ControlNet uses the garment_img to guide the inpainting inside the mask
    final_image = tensorrt_diffusion_infer(
        person=user_img,
        garment=garment_img,
        mask=mask,
        num_inference_steps=20
    )
    
    # 4. Upload result and notify frontend
    result_url = upload_to_s3(final_image)
    notify_user_websocket(result_url)
```

---

## Conclusion

With VTON integrated, the Coutury architecture transitions from a simple search engine to a full **Generative AI Fashion Platform**, entirely self-hosted on a single bare-metal node.
