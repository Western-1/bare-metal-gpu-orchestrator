# Security and Network Isolation

**Component:** Kubernetes NetworkPolicy + DevSecOps  
**Objective:** Isolate workload namespaces to minimize blast radius  
**Security Model:** Zero Trust Network Segmentation  

---

## Prerequisites

Ensure k3s cluster is operational from `01-infrastructure-setup.md`:

```bash
# Verify k3s is running
kubectl get nodes

# Verify namespaces exist
kubectl get namespaces

# Verify NetworkPolicy support
kubectl api-resources | grep networkpolicies
```

---

## Step 1: Security Architecture Overview

### Zero Trust Network Model

This project implements a Zero Trust network segmentation strategy:

- **Namespace Isolation:** Each namespace has its own network policies
- **Default Deny:** All ingress/egress traffic blocked by default
- **Explicit Allow:** Only required traffic is explicitly permitted
- **Service-to-Service Control:** Workloads cannot communicate directly with each other
- **Egress Filtering:** External access controlled via allowlist

### Namespace Security Zones

| **Namespace** | **Security Zone** | **Ingress Policy** | **Egress Policy** | **Purpose** |
|---------------|-------------------|-------------------|------------------|-------------|
| `gpu-infrastructure` | Infrastructure | Allow from monitoring | Allow to registry | Device plugin, infrastructure |
| `ml-workloads` | Production | Allow from ingress | Allow to monitoring | ML inference services |
| `monitoring` | Observability | Allow from all namespaces | Allow to external | Prometheus, Grafana, DCGM |
| `argocd` | Management | Allow from admin workstation | Allow to cluster | GitOps controller |

### Threat Model

| **Threat** | **Mitigation** | **Control** |
|------------|----------------|-------------|
| **Pod-to-Pod Lateral Movement** | NetworkPolicy isolation | Namespace segmentation |
| **Compromised Workload Exfiltration** | Egress filtering | Allowlist external destinations |
| **Unauthorized API Access** | RBAC + ServiceAccount | Least privilege principles |
| **Supply Chain Attack** | Image admission controller | Image signature verification |
| **Data Exfiltration** | TLS encryption | mTLS between services |

---

## Step 2: Enable NetworkPolicy in k3s

### Verify NetworkPolicy Support

```bash
# Check if NetworkPolicy is enabled
kubectl get configmap kube-proxy -n kube-system -o yaml | grep networkPolicy

# Expected output: networkPolicy: "true"

# If not enabled, enable it:
# Edit k3s config
sudo cat /etc/rancher/k3s/config.yaml
# Add: kube-apiserver-arg: "feature-gates=NetworkPolicy=true"
# Restart k3s
sudo systemctl restart k3s
```

### Install Calico (Optional Alternative)

k3s includes built-in NetworkPolicy support via Traefik (if using CNI). For advanced features, install Calico:

```bash
# Install Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml

# Verify Calico installation
kubectl get pods -n kube-system -l k8s-app=calico-node

# Expected output: Calico pods in Running state
```

---

## Step 3: Default Deny All NetworkPolicy

### Create Default Deny Policy

```yaml
# manifests/networking/default-deny-all.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ml-workloads
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### Apply to All Namespaces

```bash
# Apply default deny to ml-workloads
kubectl apply -f manifests/networking/default-deny-all.yaml -n ml-workloads

# Apply to gpu-infrastructure
kubectl apply -f manifests/networking/default-deny-all.yaml -n gpu-infrastructure

# Apply to monitoring
kubectl apply -f manifests/networking/default-deny-all.yaml -n monitoring

# Verify policies are applied
kubectl get networkpolicies -A

# Expected output:
# NAMESPACE           NAME              POD-SELECTOR   AGE
# ml-workloads        default-deny-all   <none>          10s
# gpu-infrastructure  default-deny-all   <none>          10s
# monitoring          default-deny-all   <none>          10s
```

---

## Step 4: ML Workloads NetworkPolicy

### Allow Ingress from Ingress Controller

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

### Allow Egress to Monitoring

```yaml
# manifests/networking/ml-workloads-monitoring.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: ml-workloads
spec:
  podSelector:
    matchLabels:
      workload-type: gpu-inference
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 9090  # Prometheus
    - protocol: TCP
      port: 9400  # DCGM Exporter
```

### Allow Egress to DNS

```yaml
# manifests/networking/ml-workloads-dns.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: ml-workloads
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

### Allow Egress to Container Registry

```yaml
# manifests/networking/ml-workloads-registry.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-registry
  namespace: ml-workloads
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
    ports:
    - protocol: TCP
      port: 443  # HTTPS for GHCR/Docker Hub
```

### Deny Inter-Service Communication

```yaml
# manifests/networking/ml-workloads-deny-inter-service.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-inter-service
  namespace: ml-workloads
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          workload-type: gpu-inference
```

### Apply ML Workloads Policies

```bash
# Apply all ML workloads policies
kubectl apply -f manifests/networking/ml-workloads-ingress.yaml
kubectl apply -f manifests/networking/ml-workloads-monitoring.yaml
kubectl apply -f manifests/networking/ml-workloads-dns.yaml
kubectl apply -f manifests/networking/ml-workloads-registry.yaml
kubectl apply -f manifests/networking/ml-workloads-deny-inter-service.yaml

# Verify policies
kubectl get networkpolicies -n ml-workloads

# Expected output:
# NAME                       POD-SELECTOR              AGE
# allow-dns                  <none>                    10s
# allow-ingress              workload-type=gpu-inference  10s
# allow-monitoring           workload-type=gpu-inference  10s
# allow-registry             <none>                    10s
# default-deny-all           <none>                    30s
# deny-inter-service         <none>                    10s
```

---

## Step 5: GPU Infrastructure NetworkPolicy

### Allow Ingress from Monitoring

```yaml
# manifests/networking/gpu-infrastructure-monitoring.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: gpu-infrastructure
spec:
  podSelector:
    matchLabels:
      app: nvidia-device-plugin
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 9400
```

### Allow Egress to Kubernetes API

```yaml
# manifests/networking/gpu-infrastructure-k8s-api.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-k8s-api
  namespace: gpu-infrastructure
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 10.0.0.0/8  # Kubernetes service CIDR
    ports:
    - protocol: TCP
      port: 443
```

### Apply GPU Infrastructure Policies

```bash
# Apply GPU infrastructure policies
kubectl apply -f manifests/networking/gpu-infrastructure-monitoring.yaml
kubectl apply -f manifests/networking/gpu-infrastructure-k8s-api.yaml

# Verify policies
kubectl get networkpolicies -n gpu-infrastructure
```

---

## Step 6: Monitoring NetworkPolicy

### Allow Ingress from All Namespaces

```yaml
# manifests/networking/monitoring-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-ingress
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app: prometheus
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 9090
```

### Allow Egress to All Namespaces

```yaml
# manifests/networking/monitoring-egress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-egress
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app: prometheus
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector: {}
```

### Allow Grafana External Access

```yaml
# manifests/networking/monitoring-grafana.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-grafana-external
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app: grafana
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 0.0.0.0/0  # Allow external access via NodePort
    ports:
    - protocol: TCP
      port: 3000
```

### Apply Monitoring Policies

```bash
# Apply monitoring policies
kubectl apply -f manifests/networking/monitoring-ingress.yaml
kubectl apply -f manifests/networking/monitoring-egress.yaml
kubectl apply -f manifests/networking/monitoring-grafana.yaml

# Verify policies
kubectl get networkpolicies -n monitoring
```

---

## Step 7: Service Account and RBAC

### Create Dedicated ServiceAccounts

```yaml
# manifests/rbac/ml-workloads-serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: embedding-service
  namespace: ml-workloads
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vision-service
  namespace: ml-workloads
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: background-worker
  namespace: ml-workloads
automountServiceAccountToken: false
```

### Update Deployments to Use ServiceAccounts

```yaml
# Update embedding-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: embedding-service
  namespace: ml-workloads
spec:
  template:
    spec:
      serviceAccountName: embedding-service
      # ... rest of deployment spec
```

### Apply ServiceAccounts

```bash
# Apply ServiceAccounts
kubectl apply -f manifests/rbac/ml-workloads-serviceaccount.yaml

# Update deployments to reference ServiceAccounts
kubectl patch deployment embedding-service -n ml-workloads -p '{"spec":{"template":{"spec":{"serviceAccountName":"embedding-service"}}}}'
kubectl patch deployment vision-service -n ml-workloads -p '{"spec":{"template":{"spec":{"serviceAccountName":"vision-service"}}}}'
kubectl patch deployment background-worker -n ml-workloads -p '{"spec":{"template":{"spec":{"serviceAccountName":"background-worker"}}}}'

# Verify ServiceAccounts
kubectl get serviceaccounts -n ml-workloads
```

---

## Step 8: Pod Security Standards

### Apply Pod Security Admission

```bash
# Label namespaces with Pod Security standards
kubectl label --overwrite ns ml-workloads pod-security.kubernetes.io/enforce=restricted
kubectl label --overwrite ns gpu-infrastructure pod-security.kubernetes.io/enforce=baseline
kubectl label --overwrite ns monitoring pod-security.kubernetes.io/enforce=privileged

# Verify labels
kubectl get namespaces --show-labels
```

### Update Security Context in Deployments

```yaml
# Update deployment security context
apiVersion: apps/v1
kind: Deployment
metadata:
  name: embedding-service
  namespace: ml-workloads
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: embedding-service
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
```

### Apply Security Context Updates

```bash
# Patch deployments with security context
kubectlpatch deployment embedding-service -n ml-workloads --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/securityContext",
    "value": {
      "runAsNonRoot": true,
      "runAsUser": 1000,
      "fsGroup": 1000
    }
  }
]'
```

---

## Step 9: Verify Network Isolation

### Test Inter-Service Communication (Should Fail)

```bash
# Test that embedding service cannot reach vision service
kubectl exec -n ml-worklights deployment/embedding-service -- curl -s http://vision-service:8001/health

# Expected output: Connection refused or timeout (NetworkPolicy blocking)
```

### Test Monitoring Access (Should Succeed)

```bash
# Test that monitoring can scrape metrics
kubectl exec -n monitoring deployment/kube-prometheus-stack-prometheus -- curl -s http://embedding-service.ml-workloads.svc.cluster.local:8000/health

# Expected output: {"status":"healthy",...} (NetworkPolicy allows)
```

### Test DNS Resolution

```bash
# Test DNS resolution from pods
kubectl exec -n ml-workloads deployment/embedding-service -- nslookup kubernetes.default.svc.cluster.local

# Expected output: DNS resolution succeeds (NetworkPolicy allows)
```

### Test Egress to External

```bash
# Test egress to external registry
kubectl exec -n ml-workloads deployment/embedding-service -- curl -s https://ghcr.io

# Expected output: HTTP response (NetworkPolicy allows)
```

---

## Step 10: Security Best Practices

### Image Security

```bash
# Use signed images
# Configure admission controller to verify image signatures

# Scan images for vulnerabilities
trivy image your-registry/embedding-service:latest

# Use minimal base images
# Prefer python:3.11-slim over python:3.11
```

### Secrets Management

```bash
# Use Kubernetes secrets for sensitive data
kubectl create secret generic api-keys -n ml-workloads \
  --from-literal=api-key=your-api-key

# Mount secrets as volumes (not environment variables)
# Update deployment to use secret volumes
```

### Audit Logging

```bash
# Enable audit logging in k3s
sudo cat /etc/rancher/k3s/config.yaml
# Add:
# audit-log-file: /var/lib/rancher/k3s/server/logs/audit.log
# audit-log-maxage: 30
# audit-log-maxsize: 100
# audit-log-maxbackup: 10

# Restart k3s
sudo systemctl restart k3s
```

### Network Policies as Code

```bash
# Store NetworkPolicies in Git repository
# Apply via ArgoCD (from 05-gitops-cicd.md)
# This ensures NetworkPolicy changes are versioned and reviewed
```

---

## Verification Checklist

### ✅ NetworkPolicy Verification

```bash
# 1. Default deny policy is applied to all namespaces
kubectl get networkpolicies -A | grep default-deny-all
# Expected: 3 policies (one per namespace)

# 2. Inter-service communication is blocked
kubectl exec -n ml-workloads deployment/embedding-service -- curl http://vision-service:8001/health
# Expected: Connection refused/timeout

# 3. Monitoring can scrape metrics
kubectl exec -n monitoring deployment/kube-prometheus-stack-prometheus -- curl http://embedding-service.ml-workloads.svc.cluster.local:8000/health
# Expected: Success
```

### ✅ RBAC Verification

```bash
# 4. ServiceAccounts are created
kubectl get serviceaccounts -n ml-workloads
# Expected: embedding-service, vision-service, background-worker

# 5. Deployments use ServiceAccounts
kubectl get deployment embedding-service -n ml-workloads -o yaml | grep serviceAccountName
# Expected: embedding-service
```

### ✅ Pod Security Verification

```bash
# 6. Namespaces have Pod Security labels
kubectl get namespaces --show-labels | grep pod-security
# Expected: All namespaces labeled

# 7. Pods run as non-root
kubectl get pods -n ml-workloads -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext.runAsNonRoot}{"\n"}{end}'
# Expected: All pods show true
```

---

## Troubleshooting

### Issue: Pods cannot resolve DNS

**Symptom:** Pods report "lookup failure" for service names.

**Solution:**
```bash
# Check DNS NetworkPolicy
kubectl get networkpolicy allow-dns -n ml-workloads

# If missing, apply DNS policy
kubectl apply -f manifests/networking/ml-workloads-dns.yaml

# Check CoreDNS is running
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

### Issue: Monitoring cannot scrape metrics

**Symptom:** Prometheus targets show "down" for workloads.

**Solution:**
```bash
# Check monitoring egress policy
kubectl get networkpolicy allow-monitoring -n ml-workloads

# Check workload ingress policy
kubectl get networkpolicy allow-ingress -n ml-workloads

# Verify policy allows monitoring namespace
kubectl get networkpolicy allow-monitoring -n ml-workloads -o yaml | grep monitoring
```

### Issue: Pods cannot pull images

**Symptom:** Pods stuck in ImagePullBackOff state.

**Solution:**
```bash
# Check registry egress policy
kubectl get networkpolicy allow-registry -n ml-workloads

# Test egress from pod
kubectl exec -n ml-workloads deployment/embedding-service -- curl -v https://ghcr.io

# If blocked, update policy to allow registry CIDR
```

### Issue: Service-to-service communication blocked unexpectedly

**Symptom:** Legitimate service communication fails.

**Solution:**
```bash
# Check deny-inter-service policy
kubectl get networkpolicy deny-inter-service -n ml-workloads

# If too restrictive, add exceptions:
kubectl edit networkpolicy deny-inter-service -n ml-workloads
# Add specific podSelector exceptions
```

---

## Summary

With security and network isolation configured, you achieve:

- **Zero Trust Network Segmentation** with namespace-level isolation
- **Default Deny** policy blocking all unauthorized traffic
- **Explicit Allow** rules for required communication paths
- **Inter-Service Isolation** preventing lateral movement
- **RBAC Least Privilege** with dedicated ServiceAccounts
- **Pod Security Standards** enforcing secure container configurations
- **Blast Radius Minimization** limiting impact of compromised workloads

This DevSecOps strategy ensures your bare-metal GPU cluster maintains production-grade security standards while enabling safe multi-tenant ML inference operations.

---

## Next Steps

With security isolation complete, proceed to:

**Document 10:** `10-disaster-recovery.md`

This document covers:
- Disaster Recovery plan using Velero
- Automated backup scheduling to MinIO (S3)
- Cluster state backup and restore methodology
- Recovery time objective (RTO) and recovery point objective (RPO) definitions
