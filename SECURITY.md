# Security Policy

## Supported Versions

Only the latest major version of this architecture is supported with security updates.

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take the security of our MLOps infrastructure seriously. If you discover a vulnerability (e.g., potential unauthorized access to the MLflow instance, VRAM isolation bypass, or arbitrary code execution within the KubeRay cluster), please do **NOT** open a public issue.

Instead, please report the vulnerability privately:
1. Email your findings to `security@internal.corp` (or the lead maintainer).
2. Include steps to reproduce the exploit.
3. Wait for an acknowledgment (typically within 48 hours).

We will coordinate a patch, test it against the local bare-metal cluster, and release a CVE/Advisory if applicable before disclosing the vulnerability publicly.
