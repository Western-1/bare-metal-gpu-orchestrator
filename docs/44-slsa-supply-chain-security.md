# Supply Chain Security (SLSA)

**Component:** Image Signing & Verification  
**Objective:** Prevent unauthorized container images from executing in the cluster  
**Architecture:** Sigstore / Cosign + Kyverno Admission Controller  

---

## 1. Supply Chain Attack Vectors

In a GitOps environment (`05-gitops-cicd.md`), ArgoCD autonomously pulls new Docker images based on manifest changes. If an attacker compromises the Harbor container registry or intercepts the CI pipeline to inject malicious code into the `vllm-openai:latest` image, the cluster will unknowingly pull and execute it.

Vulnerability scanning (Trivy) is insufficient, as it only detects known CVEs, not targeted malicious backdoors.

---

## 2. SLSA Level 3 Compliance

The Supply-chain Levels for Software Artifacts (SLSA) framework defines standards for artifact integrity. Level 3 requires that:
1. The build environment is ephemeral and isolated (GitHub Actions).
2. The output artifact (Docker image) is cryptographically signed.
3. The signature's provenance (who built it and where) is verifiable.

---

## 3. Implementing Sigstore / Cosign

### 3.1 CI/CD Signing

Within the GitHub Actions pipeline, after the image is built and pushed to the registry, it is signed using **Cosign**. Cosign utilizes keyless signing (OIDC) to bind the signature directly to the GitHub repository identity.

```yaml
# .github/workflows/build.yml excerpt
    steps:
      - name: Build and Push
        id: docker_build
        uses: docker/build-push-action@v4
        with:
          push: true
          tags: internal-registry.corp/vision-service:${{ github.sha }}

      - name: Sign the Image
        run: |
          cosign sign --yes \
            internal-registry.corp/vision-service@${{ steps.docker_build.outputs.digest }}
```

### 3.2 Kubernetes Admission Control (Kyverno)

To enforce this at the infrastructure layer, deploy **Kyverno** as a Mutating/Validating Admission Webhook. Kyverno intercepts every `Pod` creation request. If the image lacks a valid cryptographic signature matching the corporate OIDC issuer, the Kubernetes API Server rejects the deployment.

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno -n kyverno --create-namespace
```

**Validation Policy:**

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: check-image-signature
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-cosign
      match:
        resources:
          kinds:
            - Pod
      verifyImages:
        - imageReferences:
            - "internal-registry.corp/*"
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/YourOrg/DevOps-Repo/.github/workflows/build.yml@refs/heads/master"
                    issuer: "https://token.actions.githubusercontent.com"
```

**Result:** Any image not built by the official CI pipeline will yield:
`Error from server: admission webhook "validate.kyverno.svc" denied the request: image signature verification failed.`

---

## Next Steps

Proceed to `45-energy-attribution-kepler.md` to track the exact Watt-Hour consumption of these secured workloads.
