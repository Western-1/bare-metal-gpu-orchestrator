# Confidential Computing (TEE)

**Component:** Hardware Security  
**Objective:** Protect proprietary model weights from Host OS interception  
**Architecture:** NVIDIA Confidential Computing (CC)  

---

## 1. The Host Administrator Threat Vector

In standard bare-metal deployments (even with strict NetworkPolicies and Istio mTLS), a fundamental vulnerability exists: **The Host OS Administrator**.

If a malicious actor gains `root` access to the Ubuntu host running the k3s cluster, they can dump the contents of system RAM or GPU VRAM using low-level kernel tracing tools or PCIe memory scanning. For organizations deploying proprietary foundation models (where training cost millions of dollars), the weights themselves are the most critical intellectual property.

---

## 2. Trusted Execution Environments (TEE)

To mitigate this, the architecture employs **Confidential Computing (CC)**. 
*Note: This specific capability requires Hopper (H100) or Ampere (A100) enterprise silicon. Consumer RTX cards do not support hardware CC.*

A TEE establishes a hardware-enforced encrypted boundary around the CPU, Memory, and GPU VRAM.
1. The CPU encrypts data before sending it over the PCIe bus.
2. The GPU decrypts the data internally, computes the matrix multiplication, and encrypts the output before sending it back.
3. **Result:** Even the Hypervisor or Root Host OS sees only ciphertext if it attempts to read the VRAM.

---

## 3. NVIDIA CC Configuration

### 3.1 Host OS Preparation

Enable Secure Boot and verify the CPU supports AMD SEV-SNP or Intel TDX (required to establish the root of trust).

```bash
# Verify CC status on the NVIDIA driver
nvidia-smi conf-compute -s
```

### 3.2 Attestation Process

Before the ML Pod loads the proprietary weights, it must verify the cryptographic integrity of the environment to ensure it is not running in a simulated or compromised GPU.

1. The Pod requests an Attestation Report from the NVIDIA driver.
2. The Pod sends this report to a remote Key Management Server (KMS).
3. The KMS cryptographically verifies the signature matches NVIDIA's hardware root certificate.
4. If verified, the KMS releases the decryption key to the Pod, allowing it to decrypt the model weights directly into the TEE VRAM.

### 3.3 Kubernetes Deployment

To deploy a confidential workload, instruct the NVIDIA Device Plugin to allocate CC-enabled GPUs.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: confidential-inference
spec:
  runtimeClassName: nvidia-cc  # Triggers the confidential containerd runtime
  containers:
  - name: inference-engine
    image: proprietary-vllm:secure
    resources:
      limits:
        # Request Confidential Computing GPU
        nvidia.com/gpucc: 1
```

---

## 4. Trade-offs

- **Performance Penalty:** PCIe encryption and decryption introduce a 5-15% throughput penalty depending on the workload intensity.
- **Hardware Limitations:** Not applicable to the Time-Slicing consumer topologies; requires dedicated Enterprise procurement.

---

## Next Steps

Proceed to `44-slsa-supply-chain-security.md` to secure the container image pipeline.
