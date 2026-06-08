# Canary Deployments and A/B Testing

**Component:** Traffic Routing  
**Objective:** Statistically validate new model accuracy in production safely  
**Architecture:** Istio VirtualServices & DestinationRules  

---

## 1. The Deployment Risk

When an updated model (e.g., `v2.0` of the Vision Classifier) passes the automated LLM-as-a-Judge evaluations (`40-automated-model-evaluation.md`), deploying it instantaneously to 100% of live production traffic carries immense business risk. 

If the model hallucinates in edge cases not captured by the evaluation dataset, all users are impacted simultaneously. 

---

## 2. Canary Architecture (Istio)

Utilizing the Istio Service Mesh (`28-service-mesh-istio.md`), the architecture decouples the physical Pod deployment from the HTTP traffic routing. This enables **Canary Deployments**.

1. The `v1.0` model (Stable) serves 100% of traffic.
2. The `v2.0` model (Canary) is deployed to the cluster. Both run concurrently in distinct GPU Time-Slices.
3. Istio routes precisely 5% of incoming HTTP requests to `v2.0`.
4. Over 24 hours, Prometheus monitors the error rates, latency, and business metrics (drift) of the 5% Canary.
5. If successful, ArgoCD updates the Istio manifest to route 100% to `v2.0`.

---

## 3. Istio Traffic Split Implementation

To achieve this, the Kubernetes Deployment must label the pods with their specific versions.

### 3.1 Destination Rule

Define subsets based on the version labels.

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: vision-service-dest
  namespace: ml-workloads
spec:
  host: vision-service
  subsets:
  - name: v1
    labels:
      version: "1.0"
  - name: v2
    labels:
      version: "2.0"
```

### 3.2 Virtual Service (Traffic Split)

Instruct the Envoy sidecars to apply a weighted routing algorithm. 95% of traffic flows to the established `v1` subset, while 5% acts as the statistical canary against `v2`.

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: vision-service-routing
  namespace: ml-workloads
spec:
  hosts:
  - vision-service
  http:
  - route:
    - destination:
        host: vision-service
        subset: v1
      weight: 95
    - destination:
        host: vision-service
        subset: v2
      weight: 5
```

---

## 4. Shadow Traffic (Dark Launching)

Alternatively, for zero-risk A/B testing, Istio can perform **Traffic Mirroring**. 100% of user traffic is routed to `v1` and the user receives the `v1` response. However, Envoy duplicates the HTTP payload and sends a "fire-and-forget" copy to `v2`. 

```yaml
# Istio Mirroring Excerpt
  http:
  - route:
    - destination:
        host: vision-service
        subset: v1
    mirror:
      host: vision-service
      subset: v2
    mirrorPercentage:
      value: 100.0
```

This ensures the `v2` model is tested against real production scale and inputs without ever impacting the user-facing latency or output.

---

## Next Steps

Proceed to `49-gpu-direct-storage.md` to optimize the physical loading of these models.
