# 13. API Gateway and Rate Limiting

GPU compute is an extremely expensive resource. Allowing unauthenticated or unthrottled access to your AI APIs leaves you vulnerable to resource exhaustion attacks (DDoS) and spam, which can queue up the GPU and block legitimate users.

To protect the Time-Sliced replicas, we will configure the NGINX Ingress Controller to act as an API Gateway, strictly rate-limiting incoming requests.

---

## NGINX Rate Limiting Annotations

The NGINX Ingress Controller supports rate limiting out-of-the-box via annotations. 

We will implement two layers of limits:
1. **Request Rate Limit (`limit-rps`):** Caps the number of requests per second from a single IP address (e.g., 5 req/sec).
2. **Connection Limit (`limit-connections`):** Caps the number of concurrent connections from a single IP address (e.g., 10 connections).

### Example YAML Configuration

Apply this Ingress manifest to securely expose the embedding service:

```yaml
# manifests/networking/api-rate-limited-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress-rate-limited
  namespace: ml-workloads
  annotations:
    # Use Let's Encrypt for HTTPS
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    
    # --- RATE LIMITING ---
    # Limit requests to 5 per second per IP
    nginx.ingress.kubernetes.io/limit-rps: "5"
    
    # Limit concurrent connections to 10 per IP
    nginx.ingress.kubernetes.io/limit-connections: "10"
    
    # Return HTTP 429 (Too Many Requests) when limits are exceeded
    nginx.ingress.kubernetes.io/limit-rate-status: "429"
    
    # Allow a burst of 10 requests to queue before rejecting
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

### Explaining the Burst Multiplier
If the `limit-rps` is 5, and the `limit-burst-multiplier` is 2, NGINX will allow a burst of up to 10 requests (5 * 2) from a single IP to queue up and be processed at the target rate before it starts dropping requests with a 429 status code. This handles natural micro-bursts of traffic smoothly.

---

## Verifying Rate Limits

You can verify the rate limit is working by using a load testing tool like `hey` or a simple bash loop.

```bash
# Send 20 concurrent requests
for i in {1..20}; do curl -s -o /dev/null -w "%{http_code}\n" https://api.yourdomain.com/embedding & done
```

**Expected Output:** You should see a mix of `200` (OK) and `429` (Too Many Requests).

### NGINX Logs
To view rate-limiting rejections in the NGINX logs:
```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx | grep "limiting requests"
```
