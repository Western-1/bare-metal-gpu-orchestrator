# Remote Server Deployment and Security

**Component:** Perimeter Security and Ingress Control  
**Objective:** Secure bare-metal remote GPU clusters (e.g., Hetzner, Lambda Labs)  
**Security Model:** UFW Hardening, TLS Encryption, Nginx Basic Auth  

---

## 1. Host Perimeter Hardening (UFW)

Bare-metal deployments lack cloud-provider security groups. Host-level iptables/UFW configurations are mandatory to prevent unauthorized access to the k3s API (port 6443) and NodePorts.

### UFW Configuration

Apply a strict default-deny ingress policy while permitting internal CNI traffic.

```bash
# Update SSH daemon port
# sudo nano /etc/ssh/sshd_config (Change Port 22 to 2222)
# sudo systemctl restart sshd

sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow designated SSH port
sudo ufw allow 2222/tcp

# Allow HTTP/HTTPS for Nginx Ingress
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Whitelist k3s internal CNI networking (Flannel)
sudo ufw allow in on cni0
sudo ufw allow in on flannel.1
sudo ufw allow 10.42.0.0/16  # Pod CIDR
sudo ufw allow 10.43.0.0/16  # Service CIDR

sudo ufw enable
```

---

## 2. Ingress TLS Encryption (cert-manager)

Public APIs require TLS termination. This implementation utilizes `cert-manager` for automated Let's Encrypt certificate provisioning.

### Install cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
kubectl get pods -n cert-manager
```

### ClusterIssuer Configuration

```yaml
# manifests/security/letsencrypt-prod.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: security@yourdomain.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

```bash
kubectl apply -f manifests/security/letsencrypt-prod.yaml
```

### Ingress Manifest Integration

```yaml
# manifests/networking/api-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  namespace: ml-workloads
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - api.yourdomain.com
    secretName: api-tls-secret
  rules:
  - host: api.yourdomain.com
    http:
      paths:
      - path: /embedding
        pathType: Prefix
        backend:
          service:
            name: embedding-service
            port:
              number: 8000
```

---

## 3. Public Endpoint Authentication (Grafana)

Internal observability endpoints exposed publicly must implement Defense in Depth. Layer Nginx Basic Authentication over Grafana's application authentication.

### Generate Authentication Secret

```bash
# Install apache2-utils locally or on jump host
sudo apt-get install apache2-utils -y

# Generate htpasswd credential file
htpasswd -c auth admin_user

# Inject into cluster
kubectl create secret generic basic-auth -n monitoring --from-file=auth
```

### Ingress Basic Auth Integration

```yaml
# manifests/monitoring/grafana-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - grafana.yourdomain.com
    secretName: grafana-tls-secret
  rules:
  - host: grafana.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 80
```

---

## Next Steps

Proceed to `12-model-caching-pvc.md` to configure high-performance PersistentVolumeClaims for model weight caching.
