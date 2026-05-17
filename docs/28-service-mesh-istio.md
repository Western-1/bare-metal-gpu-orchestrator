# Service Mesh (Istio) and mTLS

**Component:** Networking / Service Mesh  
**Objective:** Zero-Trust intra-cluster communication and Traffic Control  
**Architecture:** Istio Envoy Sidecars  

---

## 1. Limitations of Kubernetes Native Networking

While Kubernetes `NetworkPolicy` (`09-security-and-network-isolation.md`) enforces strict L3/L4 routing, it falls short for Enterprise MLOps:
- **Unencrypted Traffic:** Pod-to-Pod traffic (e.g., FastAPI calling Redis, Ray workers exchanging tensors) is transmitted in plaintext.
- **Dumb Routing:** Kubernetes `Service` load balancing operates randomly (Round-Robin). It cannot route based on HTTP headers or gRPC latency.
- **Failures:** Standard networking cannot automatically retry failed inferences or trigger circuit breakers if a GPU pod is saturated.

---

## 2. Istio Envoy Sidecar Topology

Istio mitigates these limitations by injecting a high-performance Envoy proxy (Sidecar) alongside every ML container in a Pod. All ingress and egress traffic traverses the proxy, establishing a decentralized data plane controlled by the Istio Control Plane (istiod).

### Core Capabilities

1. **Mutual TLS (mTLS):** Envoy automatically encrypts all internal communication. The FastAPI server and the Redis queue authenticate each other via cryptographic certificates without modifying application code.
2. **Circuit Breaking:** If a Time-Sliced GPU pod exceeds 95% CPU utilization and response times spike, Istio temporarily ejects it from the load-balancing pool to prevent cascading failures.
3. **Advanced gRPC Routing:** Crucial for OpenTelemetry and Ray, Istio balances persistent gRPC streams intelligently across Time-Sliced replicas.

---

## 3. Deployment Configuration

### 3.1 Install Istio

```bash
# Download and install Istio CLI
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# Install the minimal profile suitable for bare-metal
istioctl install --set profile=minimal -y
```

### 3.2 Enable Sidecar Injection

Label the target namespace to instruct the mutating admission webhook to automatically inject Envoy sidecars into all newly scheduled pods.

```bash
kubectl label namespace ml-workloads istio-injection=enabled

# Restart deployments to inject proxies
kubectl rollout restart deployment embedding-service -n ml-workloads
kubectl rollout restart deployment vision-service -n ml-workloads
```

---

## 4. Traffic Control Rules

### Enforce Strict mTLS

Mandate encrypted communication universally across the namespace.

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: strict-mtls
  namespace: ml-workloads
spec:
  mtls:
    mode: STRICT
```

### Circuit Breaker Configuration

Prevent FastAPI endpoints from cascading failure under extreme load.

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: embedding-circuit-breaker
  namespace: ml-workloads
spec:
  host: embedding-service
  trafficPolicy:
    connectionPool:
      http:
        http1MaxPendingRequests: 100
        maxRequestsPerConnection: 10
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```

---

## Next Steps

Proceed to `29-nccl-rdma-networking.md` to optimize multi-node tensor communication bypassing TCP/IP.
