# Runtime Security & Threat Detection (Falco)

**Component:** Kubernetes Runtime Protection  
**Objective:** Detect and block anomalous syscalls and container escapes  
**Architecture:** Falco + eBPF / OPA Gatekeeper  

---

## 1. The Container Escape Threat

In our bare-metal architecture, containers have significant privileges:
- They mount high-speed NVMe HostPaths (`25-storage-io-optimization.md`).
- They communicate directly with the NVIDIA GPU kernel driver (`02-gpu-time-slicing-config.md`).

If an attacker discovers a Remote Code Execution (RCE) vulnerability in the FastAPI wrapper or a Python dependency (e.g., malicious PyPI package), they could attempt to open a reverse shell inside the Pod, manipulate the HostPath filesystem, or escalate privileges to the underlying Ubuntu OS.

---

## 2. Preventive Security (OPA / Kyverno)

The first line of defense is preventing malicious configurations from being deployed.

**Pod Security Standards (PSS):** Ensure all namespaces enforce the `Restricted` or `Baseline` profile. This prevents Pods from running as `root`, mounting the host network, or acquiring `privileged: true` escalation.

```yaml
# Enforce baseline security on ML namespaces
apiVersion: v1
kind: Namespace
metadata:
  name: ml-workloads
  labels:
    pod-security.kubernetes.io/enforce: baseline
```

---

## 3. Detective Security (Falco)

Preventive measures are insufficient against zero-day exploits. **Falco** is a cloud-native runtime security tool that uses eBPF (Extended Berkeley Packet Filter) to monitor system calls (syscalls) at the Linux kernel level in real-time.

### 3.1 Falco Deployment

Deploy Falco as a DaemonSet across the bare-metal nodes.

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set driver.kind=ebpf
```

### 3.2 Defining Threat Rules

Falco operates on a rules engine. If a process inside a container behaves anomalously, Falco triggers an alert.

```yaml
# custom-falco-rules.yaml
customRules:
  # Rule 1: A shell is spawned inside an ML inference container
  - rule: Terminal shell in container
    desc: A shell was used as the entrypoint/exec point into a container with an attached terminal.
    condition: >
      spawned_process and container
      and shell_procs and proc.tty != 0
    output: "A shell was spawned in a container (user=%user.name container_id=%container.id command=%proc.cmdline)"
    priority: WARNING

  # Rule 2: Unexpected modification of the Model Cache
  - rule: Unauthorized write to HuggingFace Cache
    desc: Detects write operations to the shared model HostPath by non-approved binaries
    condition: >
      open_write and container and fd.name startswith "/root/.cache/huggingface"
      and proc.name != "python"
    output: "Non-python binary attempting to write to model cache (command=%proc.cmdline)"
    priority: CRITICAL
```

### 3.3 Response Automation (Falcosidekick)

When Falco detects a CRITICAL event (e.g., a reverse shell), it forwards the payload to **Falcosidekick**, which can trigger an automated response:
- Send an alert to Slack/PagerDuty.
- Trigger a serverless function to instantly label the compromised Pod as `quarantined=true`, causing Istio to drop its network routes and Kubernetes to terminate it.

---

## Next Steps

Proceed to `54-ml-pipeline-orchestration.md` to automate the data-to-deployment DAG workflows.
