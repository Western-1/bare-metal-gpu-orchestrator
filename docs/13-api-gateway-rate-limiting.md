# API Gateway and Rate Limiting

**Component:** NGINX Ingress Controller  
**Objective:** Prevent GPU resource exhaustion attacks via API throttling  
**Traffic Control:** Token Bucket Algorithm (RPS & Connections)  

---

## 1. Rate Limiting Architecture

Unauthenticated or unthrottled access to GPU endpoints exposes the Time-Sliced architecture to severe queuing delays and Denial of Service (DoS) vectors. 

To mitigate abuse, the NGINX Ingress Controller acts as the API Gateway enforcing two layers of throttling:
1. **Request Rate Limit (`limit-rps`):** Caps requests per second (req/sec) originating from a single IP.
2. **Connection Limit (`limit-connections`):** Caps concurrent TCP connections from a single IP.

---

## 2. Ingress Rate Limiting Manifest

Deploy the following configuration to enforce limits via NGINX ingress annotations:

```yaml
# manifests/networking/api-rate-limited-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress-rate-limited
  namespace: ml-workloads
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    
    # Restrict traffic to 5 req/sec per IP
    nginx.ingress.kubernetes.io/limit-rps: "5"
    
    # Restrict concurrent connections to 10 per IP
    nginx.ingress.kubernetes.io/limit-connections: "10"
    
    # Return HTTP 429 when limits are breached
    nginx.ingress.kubernetes.io/limit-rate-status: "429"
    
    # Allow a burst queue of 10 requests (5 RPS * 2) before strict rejection
    nginx.ingress.kubernetes.io/limit-burst-multiplier: "2" 
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

```bash
kubectl apply -f manifests/networking/api-rate-limited-ingress.yaml
```

---

## 3. Verification and Telemetry

Validate the rate limiting enforcement by simulating a traffic burst.

```bash
# Execute 20 concurrent requests
for i in {1..20}; do curl -s -o /dev/null -w "%{http_code}\n" https://api.yourdomain.com/embedding & done
```

**Validation:** The stdout output must yield a combination of `200` (Accepted) and `429` (Too Many Requests).

### Audit Rejection Logs

To monitor suppressed traffic patterns, parse the ingress controller logs:

```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx | grep "limiting requests"
```

---

## Next Steps

Proceed to `14-alerting-and-incident-response.md` to configure PagerDuty integration and anomaly detection.
