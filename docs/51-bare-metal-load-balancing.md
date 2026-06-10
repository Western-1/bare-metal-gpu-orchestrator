# Bare-Metal Load Balancing (MetalLB)

**Component:** Ingress & Network Routing  
**Objective:** Expose internal Kubernetes Services to the external bare-metal network  
**Architecture:** MetalLB (L2/BGP) + Nginx Ingress  

---

## 1. The Bare-Metal Routing Problem

In a managed cloud environment (AWS EKS, GCP GKE), deploying a Kubernetes `Service` of type `LoadBalancer` automatically provisions an external cloud load balancer and assigns a public IP address.

In a bare-metal k3s deployment, this functionality does not exist natively. By default, k3s utilizes `ServiceLB` (Klipper), which simply binds host ports (e.g., 80/443) directly to the node's IP. This approach fails to provide High Availability (HA), prevents assigning multiple virtual IPs, and creates port conflicts if multiple Ingress controllers are deployed.

---

## 2. MetalLB Architecture

**MetalLB** resolves this by hooking into your existing bare-metal network router. It allows you to assign a dedicated pool of IP addresses (from your local subnet) to Kubernetes Services.

MetalLB operates in two modes:
1. **Layer 2 Mode (ARP/NDP):** A single node assumes leadership for a specific IP and responds to ARP requests. If the node dies, leadership fails over to another node. Simplest to configure.
2. **BGP Mode:** All nodes establish BGP peering sessions with the top-of-rack router. Traffic is actively load-balanced (ECMP) across all healthy nodes simultaneously. Essential for massive throughput.

---

## 3. Implementation (Layer 2 Mode)

### 3.1 Disable Default ServiceLB
If k3s was installed without `--disable servicelb`, you must reconfigure the k3s systemd service to disable Klipper before deploying MetalLB.

### 3.2 Deploy MetalLB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml
```

### 3.3 Configure the IP Address Pool

Define a range of IPs available on your physical network router (e.g., your corporate LAN or datacenter DMZ) that are *not* assigned to physical hosts via DHCP.

```yaml
# ip-pool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.0.200-10.0.0.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
```

### 3.4 Ingress Controller Integration

Update the Nginx Ingress Controller (or Istio Ingress Gateway) to utilize the LoadBalancer type.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  type: LoadBalancer
  ports:
    - name: http
      port: 80
      protocol: TCP
      targetPort: http
    - name: https
      port: 443
      protocol: TCP
      targetPort: https
```

**Result:** MetalLB will automatically assign the first available IP (e.g., `10.0.0.200`) to the Ingress controller. Clients outside the cluster can now route traffic to this highly available Virtual IP.

---

## Next Steps

Proceed to `52-llm-guardrails.md` to secure the incoming API traffic against malicious LLM prompts.
