# Security and Network Isolation

**Component:** Kubernetes NetworkPolicy + DevSecOps  
**Objective:** Isolate workload namespaces to minimize blast radius  
**Security Model:** Zero Trust Network Segmentation  

---

## Prerequisites

Verify operational status of the cluster and NetworkPolicy support:

```bash
kubectl get nodes
kubectl get namespaces
kubectl api-resources | grep networkpolicies
```

---

## Step 1: Security Architecture Overview

### Zero Trust Network Model

This architecture enforces a strict Zero Trust topology:

- **Namespace Isolation:** Network boundaries strictly mapped to namespace perimeters.
- **Default Deny:** All ingress and egress traffic blocked globally by default.
- **Explicit Allow:** Inter-component traffic requires specific policy declarations.
- **Service-to-Service Control:** Workloads cannot communicate laterally.
- **Egress Filtering:** External internet access restricted to verified endpoints.

### Namespace Security Zones

| **Namespace** | **Security Zone** | **Ingress Policy** | **Egress Policy** |
|---------------|-------------------|-------------------|------------------|
| `gpu-infrastructure` | Infrastructure | Allow from monitoring | Allow to container registry |
| `ml-workloads` | Production | Allow from ingress controller | Allow to monitoring/DNS/registry |
| `monitoring` | Observability | Allow from all namespaces | Allow to external (via NodePort) |
| `argocd` | Management | Allow from admin CIDR | Allow to kubernetes API / GHCR |

---

## Step 2: Enable NetworkPolicy Control

### Validation

```bash
kubectl get configmap kube-proxy -n kube-system -o yaml | grep networkPolicy
```

If Traefik/Flannel lacks enforcement, initialize via k3s config:

```bash
# Append to /etc/rancher/k3s/config.yaml
# kube-apiserver-arg: "feature-gates=NetworkPolicy=true"
# sudo systemctl restart k3s
```

---

## Step 3: Global Default Deny Policy

Enforce a default drop posture for all traffic.

```yaml
# manifests/networking/default-deny-all.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

Execute across all operational namespaces:

```bash
for ns in ml-workloads gpu-infrastructure monitoring minio velero; do
  kubectl apply -f manifests/networking/default-deny-all.yaml -n $ns
done
kubectl get networkpolicies -A
```

---

## Step 4: ML Workloads Network Policies

### Explicit Ingress

```yaml
# manifests/networking/ml-workloads-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress
  namespace: ml-workloads
spec:
  podSelector:
    matchLabels:
      workload-type: gpu-inference
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8000
    - protocol: TCP
      port: 8001
```

### Explicit Egress (Monitoring & Registry)

```yaml
# manifests/networking/ml-workloads-egress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-required-egress
  namespace: ml-workloads
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 9090
    - protocol: TCP
      port: 9400
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
    ports:
    - protocol: TCP
      port: 443
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
```

Apply policies:

```bash
kubectl apply -f manifests/networking/ml-workloads-ingress.yaml
kubectl apply -f manifests/networking/ml-workloads-egress.yaml
```

---

## Step 5: GPU Infrastructure Network Policies

### Allow Monitoring and Kubernetes API Egress

```yaml
# manifests/networking/gpu-infrastructure-policies.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gpu-infra-policies
  namespace: gpu-infrastructure
spec:
  podSelector:
    matchLabels:
      app: nvidia-device-plugin
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 9400
  egress:
  - to:
    - ipBlock:
        cidr: 10.0.0.0/8
    ports:
    - protocol: TCP
      port: 443
```

```bash
kubectl apply -f manifests/networking/gpu-infrastructure-policies.yaml
```

---

## Step 6: Service Account Security

Drop default ServiceAccount privileges and enforce restricted profiles.

```yaml
# manifests/rbac/service-accounts.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: inference-worker
  namespace: ml-workloads
automountServiceAccountToken: false
```

Patch existing workloads to leverage strict contexts:

```bash
kubectl apply -f manifests/rbac/service-accounts.yaml
kubectl patch deployment embedding-service -n ml-workloads -p '{"spec":{"template":{"spec":{"serviceAccountName":"inference-worker"}}}}'
```

---

## Step 7: Pod Security Admission (PSA)

Enforce Kubernetes Pod Security Standards at the namespace level.

```bash
kubectl label --overwrite ns ml-workloads pod-security.kubernetes.io/enforce=restricted
kubectl label --overwrite ns gpu-infrastructure pod-security.kubernetes.io/enforce=baseline
kubectl label --overwrite ns monitoring pod-security.kubernetes.io/enforce=privileged
```

Require all workloads to run as non-root:

```bash
kubectl patch deployment embedding-service -n ml-workloads --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/securityContext", "value": {"runAsNonRoot": true, "runAsUser": 1000, "fsGroup": 1000}}
]'
```

---

## Step 8: Network Policy Verification

Validate lateral movement blocks:

```bash
kubectl exec -n ml-workloads deployment/embedding-service -- curl -s --max-time 2 http://vision-service:8001/health
# Expect: Connection timeout (Blocked)

kubectl exec -n monitoring deployment/kube-prometheus-stack-prometheus -- curl -s http://embedding-service.ml-workloads.svc.cluster.local:8000/health
# Expect: HTTP 200 JSON Response (Allowed)
```

---

## Troubleshooting

### Egress Failures (DNS/Registry)
**Condition:** Pods cannot resolve service discovery or pull images.
**Resolution:** Ensure UDP/TCP port 53 is whitelisted in the egress manifest.

### Prometheus Scraping Blocked
**Condition:** Targets report `context deadline exceeded`.
**Resolution:** Verify the `allow-required-egress` policy permits port 9090 on the monitoring namespace block.

---

## Next Steps

Proceed to `10-disaster-recovery.md` to configure state backup and cluster restoration protocols.
