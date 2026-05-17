# Secrets Management (Vault & ESO)

**Component:** External Secrets Operator (ESO) & HashiCorp Vault  
**Objective:** Secure credential injection and dynamic rotation  
**Architecture:** Zero-Trust Secret Federation  

---

## 1. The Kubernetes Secret Vulnerability

Native Kubernetes `Secret` objects provide zero cryptographic security at rest; they are merely base64-encoded strings stored in the etcd database. 

In an MLOps environment, compromising the cluster state exposes critical credentials:
- S3 / MinIO Access Keys (Model artifacts and Backups).
- Vector Database API Keys.
- External API Fallbacks (OpenAI, Anthropic tokens).
- MLflow Postgres Database passwords.

Storing these credentials in Git repositories (even within ArgoCD GitOps pipelines) is a severe security violation.

---

## 2. Architecture: Vault + External Secrets Operator

To achieve Enterprise-grade security, credentials must be stored in a dedicated cryptographic vault (e.g., HashiCorp Vault, AWS Secrets Manager) and dynamically synchronized into the cluster memory space at runtime via the **External Secrets Operator (ESO)**.

### Operational Flow
1. DevOps engineers store the raw secret inside HashiCorp Vault.
2. An `ExternalSecret` Custom Resource (CR) is defined in Kubernetes.
3. The ESO controller authenticates with Vault (via Kubernetes ServiceAccount JWT).
4. ESO fetches the payload from Vault and dynamically generates a native Kubernetes `Secret` in the target namespace.
5. If the secret in Vault is rotated, ESO automatically updates the Kubernetes `Secret` and triggers a Pod rolling restart (if integrated with Reloader).

---

## 3. ESO Deployment

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
    --namespace external-secrets \
    --create-namespace \
    --set installCRDs=true
```

---

## 4. Vault Integration

Define a `ClusterSecretStore` to instruct ESO on how to authenticate with the central HashiCorp Vault instance.

```yaml
# cluster-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.internal.corp:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "eso-role"
          serviceAccountRef:
            name: eso-service-account
            namespace: external-secrets
```

### Requesting a Secret

Developers define an `ExternalSecret` manifest in their application namespace instead of hardcoding values.

```yaml
# workloads/mlflow-external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mlflow-db-credentials
  namespace: workloads
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: mlflow-postgres-secret # The native k8s secret to generate
    creationPolicy: Owner
  data:
  - secretKey: POSTGRES_PASSWORD
    remoteRef:
      key: "mlops/mlflow/database"
      property: "password"
```

The resulting `mlflow-postgres-secret` can now be safely mounted as an environment variable into the MLflow deployment without ever exposing the raw password in Git.

---

## Next Steps

Proceed to `36-air-gapped-deployments.md` to configure offline model distribution.
