import torch
import time


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


if __name__ == "__main__":
    print("Starting background ML worker...")
    device = configure_gpu_memory(device_id=0, memory_fraction=0.20)

    # Simulate loading a model
    print("Connected to GPU. Allocated memory fraction: 0.20")

    try:
        while True:
            # Simulate polling a queue for tasks
            print("Polling for background ML tasks...")
            time.sleep(10)

            # Simulate a processing task
            print("Processing simulated task on GPU...")
            with torch.no_grad():
                dummy = torch.randn(1000, 1000, device=device)
                _ = dummy @ dummy
            print("Task complete. Awaiting next.")

    except KeyboardInterrupt:
        print("Worker shutting down.")
