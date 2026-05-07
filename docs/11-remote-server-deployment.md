# 11. Remote Server Deployment & Security

Deploying bare-metal GPU clusters on public cloud providers (e.g., Hetzner, Lambda Labs) requires strict security hardening. Unlike managed Kubernetes services (EKS, GKE), you are fully responsible for the node's perimeter security.

This guide covers hardening the host firewall, securing ingress traffic with TLS, and adding authentication to public endpoints.

---

## 1. Server Hardening (UFW)

By default, k3s exposes its API server on port 6443, and your services might be unnecessarily exposed on NodePorts. We must lock down the server using UFW (Uncomplicated Firewall).

### Configure UFW Rules

We will default to deny all incoming traffic, allowing only HTTP, HTTPS, and a custom SSH port (e.g., port 2222).

```bash
# First, change SSH port in /etc/ssh/sshd_config from 22 to 2222, then restart sshd
# sudo nano /etc/ssh/sshd_config
# sudo systemctl restart sshd

# Reset UFW to default deny
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow custom SSH port
sudo ufw allow 2222/tcp

# Allow HTTP and HTTPS for Ingress
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# IMPORTANT: Allow k3s internal pod and service networks (Flannel CNI)
# This prevents UFW from blocking internal Kubernetes traffic
sudo ufw allow in on cni0
sudo ufw allow in on flannel.1
sudo ufw allow 10.42.0.0/16  # Default k3s pod CIDR
sudo ufw allow 10.43.0.0/16  # Default k3s service CIDR

# Enable UFW
sudo ufw enable
```

---

## 2. Ingress & HTTPS (cert-manager)

To serve production APIs, you must encrypt traffic using Let's Encrypt TLS certificates.

### Install cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

# Verify installation
kubectl get pods -n cert-manager
```

### Configure Let's Encrypt ClusterIssuer

Create a `ClusterIssuer` to automatically request certificates for your domains.

```yaml
# manifests/security/letsencrypt-prod.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

Apply the issuer:
```bash
kubectl apply -f manifests/security/letsencrypt-prod.yaml
```

### Apply TLS to Ingress

Update your API ingress to use the cert-manager issuer:

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

## 3. Securing Public Endpoints (Grafana Auth)

If you are exposing Grafana publicly, you must secure it. Since we are using basic Nginx ingress, we can implement Basic Authentication via `htpasswd` to add an additional layer of security over Grafana's default login.

### Create the htpasswd Secret

Run this on your local machine or the server to generate the auth file:

```bash
# Install apache2-utils if needed
sudo apt-get install apache2-utils

# Create an auth file with a strong user password
htpasswd -c auth admin_user

# Create a Kubernetes Secret from the file
kubectl create secret generic basic-auth -n monitoring --from-file=auth
```

### Apply Basic Auth to Grafana Ingress

Add the authentication annotations to the Grafana ingress:

```yaml
# manifests/monitoring/grafana-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    # Basic Auth annotations
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

This ensures that even if Grafana has a vulnerability, attackers must first bypass the Nginx HTTP basic authentication layer.
