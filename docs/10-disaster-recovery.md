# Disaster Recovery with Velero and MinIO

**Component:** Velero + MinIO (S3-Compatible Storage)  
**Objective:** Automated cluster state backup and restore  
**RTO:** 1 hour (Recovery Time Objective)  
**RPO:** 15 minutes (Recovery Point Objective)  

---

## Prerequisites

Verify operational state of the k3s cluster and storage:

```bash
kubectl get nodes
kubectl get namespaces
df -h /var/lib/rancher/k3s
```

---

## Step 1: Disaster Recovery Architecture Overview

### Backup Strategy

This repository implements a robust backup strategy:
- **Velero:** Kubernetes-native backup/restore controller.
- **MinIO:** S3-compatible object storage acting as the backup repository.
- **Scheduled Backups:** Automated crons to meet the 15-minute RPO.
- **Namespace-Scoped Backups:** Independent schedules for critical namespaces.
- **Volume Snapshots:** Persistent volume backup executed via restic.

### Recovery Objectives

| **Objective** | **Target** | **Implementation Mechanism** |
|---------------|------------|---------------------------|
| **RTO** | 1 hour | Automated restore scripts |
| **RPO** | 15 minutes | Velero cron schedules |
| **Retention** | 30 days | Velero TTL configuration |
| **Storage** | 500GB | Local MinIO PV |

---

## Step 2: MinIO Deployment

### Deploy via Helm

```bash
helm repo add minio https://charts.min.io/
helm repo update

helm install minio minio/minio \
  --namespace minio \
  --version 5.0.14 \
  --set mode=standalone \
  --set persistence.size=500Gi \
  --set persistence.storageClass=local-path \
  --set rootUser=admin \
  --set rootPassword=minioadmin123 \
  --set consoleService.type=NodePort \
  --set consoleService.nodePort=9001 \
  --set service.type=NodePort \
  --set service.nodePort=9000
```

### Configure Bucket

Install the MinIO client (`mc`) and instantiate the backup bucket:

```bash
wget https://dl.min.io/client/mc/release/linux-amd64/archive/mc.RELEASE.2024-01-01T00-00-00Z -O mc
chmod +x mc
sudo mv mc /usr/local/bin/

mc alias set local http://localhost:9000 admin minioadmin123
mc mb local/velero-backups
```

---

## Step 3: Velero Installation

### Deploy Velero CLI and Server

```bash
wget https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-amd64.tar.gz
tar -xvf velero-v1.13.0-linux-amd64.tar.gz
sudo mv velero-v1.13.0-linux-amd64/velero /usr/local/bin/

kubectl create namespace velero

cat <<EOF > /tmp/velero-credentials
[default]
aws_access_key_id = admin
aws_secret_access_key = minioadmin123
EOF
chmod 600 /tmp/velero-credentials

velero install \
  --namespace velero \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file /tmp/velero-credentials \
  --use-volume-snapshots=false \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.minio.svc.cluster.local:9000

velero restic set default --volume-pod-labels app.kubernetes.io/instance=velero
```

*Note: `use-volume-snapshots=false` because k3s `local-path` storage lacks CSI snapshot support. Restic is leveraged for PV backups.*

---

## Step 4: Backup Schedules

### Workloads and Infrastructure Schedules

```yaml
# manifests/velero/schedules.yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: ml-workloads-daily
  namespace: velero
spec:
  schedule: "0 */4 * * *"
  template:
    includedNamespaces:
    - ml-workloads
    ttl: 720h
---
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: cluster-resources-daily
  namespace: velero
spec:
  schedule: "0 2 * * *"
  template:
    includedResources:
    - namespaces
    - persistentvolumes
    - persistentvolumeclaims
    - configmaps
    - secrets
    ttl: 720h
```

```bash
kubectl apply -f manifests/velero/schedules.yaml
velero schedule get
```

---

## Step 5: Manual Operations

### On-Demand Backup

```bash
velero backup create manual-backup-$(date +%Y%m%d) --include-namespaces ml-workloads --wait
velero backup describe manual-backup-$(date +%Y%m%d)
```

### Restore Procedure

```bash
velero restore create restore-$(date +%Y%m%d) \
  --from-backup manual-backup-$(date +%Y%m%d) \
  --wait
```

---

## Step 6: Testing & Runbooks

### Automated Monthly DR Test

```bash
#!/bin/bash
# scripts/monthly-dr-test.sh
BACKUP_NAME=$(velero backup get -o json | jq -r '.items[0].metadata.name')
TEST_NAMESPACE="dr-test-$(date +%Y%m%d)"

kubectl create namespace $TEST_NAMESPACE
velero restore create dr-test-restore \
  --from-backup $BACKUP_NAME \
  --namespace-mappings ml-workloads:$TEST_NAMESPACE \
  --wait

kubectl wait --for=condition=ready pod -l workload-type=gpu-inference -n $TEST_NAMESPACE --timeout=5m
if [ $? -eq 0 ]; then
    kubectl delete namespace $TEST_NAMESPACE
    exit 0
else
    exit 1
fi
```

Schedule via crontab:
```bash
0 3 1 * * /path/to/scripts/monthly-dr-test.sh >> /var/log/dr-test.log 2>&1
```

---

## Troubleshooting

### Velero Backup S3 Error
**Condition:** Backups fail with `AccessDenied` or `NoSuchBucket`.
**Resolution:** Validate MinIO credentials in `/tmp/velero-credentials` and ensure `velero-backups` bucket exists via `mc ls local`.

### Storage Exhaustion
**Condition:** MinIO PVC reaches 100% utilization.
**Resolution:** Force TTL enforcement via `velero backup delete --older-than 720h`. Expand the PVC if necessary.

---

## Next Steps

Proceed to `11-remote-server-deployment.md` to configure UFW, WireGuard, and SSH hardening for remote cluster management.
