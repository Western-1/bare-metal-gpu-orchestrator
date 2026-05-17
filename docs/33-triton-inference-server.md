# Triton Inference Server

**Component:** Inference Engine  
**Objective:** Maximum throughput for Vision/Audio and non-LLM models  
**Architecture:** NVIDIA Triton & TensorRT  

---

## 1. Inference Engine Limitations

While vLLM (`15-dynamic-batching-vllm.md`) provides state-of-the-art PagedAttention optimizations for generative Large Language Models, it is structurally incompatible with traditional architectures like Vision Transformers (ViT), ResNet, or Audio synthesis (Whisper).

Running these models natively in standard PyTorch or ONNX Runtime inside a FastAPI wrapper incurs significant Python overhead and cannot efficiently aggregate concurrent requests at the C++ level.

---

## 2. Triton Architecture

**NVIDIA Triton Inference Server** resolves this by operating as a high-performance C++ inference matrix.

**Key Capabilities:**
1. **Multi-Framework:** Serves TensorRT, PyTorch, ONNX, and TensorFlow models concurrently from the same server.
2. **Dynamic Batching (Hardware Level):** Intercepts independent HTTP/gRPC requests, holds them for a configurable microsecond window (e.g., 500µs), concatenates them into a single memory-aligned tensor block, executes the forward pass on the GPU, and demultiplexes the outputs back to the disparate clients.
3. **Concurrent Execution:** Triton natively leverages CUDA streams to execute independent model graphs concurrently within the same Time-Slice partition.

---

## 3. TensorRT Compilation

For maximum throughput, models must be compiled from standard PyTorch (`.pt`) into NVIDIA TensorRT format (`.plan`). This executes layer fusion, kernel auto-tuning for the specific GPU architecture (e.g., RTX 5070 Ti), and precision calibration.

```bash
# Export PyTorch to ONNX
python export_to_onnx.py --model resnet18 --output model.onnx

# Compile ONNX to TensorRT engine (execute this ON the target hardware)
trtexec --onnx=model.onnx \
        --saveEngine=model.plan \
        --fp16 \
        --workspace=2048 \
        --minShapes=input:1x3x224x224 \
        --optShapes=input:8x3x224x224 \
        --maxShapes=input:32x3x224x224
```

---

## 4. Triton Deployment

Define the Model Repository structure (stored on Ceph or HostPath NVMe):

```text
model_repository/
└── vision_classifier/
    ├── config.pbtxt
    └── 1/
        └── model.plan
```

**`config.pbtxt` Definition:**
```protobuf
name: "vision_classifier"
platform: "tensorrt_plan"
max_batch_size: 32
dynamic_batching {
  preferred_batch_size: [ 8, 16, 32 ]
  max_queue_delay_microseconds: 1000
}
```

Deploy the Triton Server targeting the repository:

```yaml
# Triton Deployment Excerpt
      containers:
      - name: triton
        image: nvcr.io/nvidia/tritonserver:latest-py3
        command: ["tritonserver", "--model-repository=/models"]
        resources:
          limits:
            nvidia.com/gpu: 1
```

---

## Next Steps

Proceed to `34-rag-vector-database.md` to persist embedding outputs.
