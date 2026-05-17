# Preemption and Spot Instance Management

**Component:** Kubernetes Node Lifecycle  
**Objective:** Ensure graceful degradation and zero data loss during sudden node termination  
**Architecture:** Node Termination Handler  

---

## 1. The Spot Instance Paradigm

To aggressively optimize operational expenses (FinOps), workloads are frequently scheduled on preemptible (Spot) bare-metal or cloud instances. These instances offer 60-80% cost reductions but carry a critical caveat: the provider can reclaim the hardware with minimal notice (typically 30 to 120 seconds).

A sudden termination event (`SIGKILL`) during a heavy PyTorch batch inference or model training iteration guarantees data corruption and dropped HTTP responses.

---

## 2. Graceful Degradation Strategy

The cluster must autonomously intercept the hardware preemption signal and execute a rigid shutdown sequence prior to the physical termination of the instance.

### Execution Sequence

1. **Detection:** Intercept the ACPI event or Cloud Provider metadata signal indicating imminent termination.
2. **Cordon:** Immediately mark the node as `Unschedulable` to prevent the Kube-Scheduler from routing new tasks to the dying host.
3. **Drain (Egress):** Remove the Node from all Kubernetes `Service` endpoints (e.g., Ingress routes stop forwarding synchronous HTTP traffic to the node).
4. **Flush (State):** Issue `SIGTERM` to the ML Pods. 
   - Background workers finalize the current active tensor and halt consumption of the Redis Queue.
   - Training processes serialize their gradients and push checkpoint artifacts to distributed storage (MinIO/Ceph).
5. **Termination:** Safely exit.

---

## 3. Node Termination Handler Deployment

For bare-metal and hybrid clusters, deploy a DaemonSet configured to monitor ACPI termination events or cloud-specific endpoints.

*Example: AWS Node Termination Handler deployed via Helm for generic spot support.*

```bash
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update

helm install aws-node-termination-handler aws-ebs-csi-driver/aws-node-termination-handler \
    --namespace kube-system \
    --set enableSpotInterruptionDraining="true" \
    --set enableRebalanceMonitoring="true" \
    --set enableRebalanceDraining="false"
```

---

## 4. Application-Layer Handling

Kubernetes signaling is insufficient without application-layer compliance. PyTorch scripts must explicitly trap the `SIGTERM` signal to execute their local checkpointing subroutines before the orchestrator issues the fatal `SIGKILL`.

### Python Signal Handler Implementation

```python
import signal
import sys
import torch
import time

class GracefulKiller:
    kill_now = False
    
    def __init__(self):
        # Bind SIGTERM (sent by Kubelet during Drain) and SIGINT
        signal.signal(signal.SIGINT, self.exit_gracefully)
        signal.signal(signal.SIGTERM, self.exit_gracefully)

    def exit_gracefully(self, *args):
        print("SIGTERM received: Initiating emergency checkpoint dump...")
        self.kill_now = True

def training_loop():
    killer = GracefulKiller()
    model = get_model()
    
    for batch_idx, batch in enumerate(dataset):
        # 1. Forward Pass / Backprop
        execute_tensor_ops(model, batch)
        
        # 2. Preemption Check
        if killer.kill_now:
            print(f"Halting at epoch {batch_idx}. Serializing state...")
            torch.save(model.state_dict(), '/mnt/cephfs/emergency_checkpoint.pt')
            sys.exit(0)
            
if __name__ == '__main__':
    training_loop()
```

### PreStop Lifecycle Hook

Optionally, configure the Kubernetes Pod manifest with a `preStop` hook to decouple signal handling from the Python runtime, executing a discrete shell script before container teardown.

```yaml
# Pod Spec Excerpt
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "python scripts/flush_queue.py"]
```
