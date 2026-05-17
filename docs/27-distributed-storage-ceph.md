# Distributed Storage (Rook/Ceph)

**Component:** Storage / PersistentVolumes  
**Objective:** Cluster-wide Shared Storage (ReadWriteMany) for ML Models  
**Architecture:** Rook Operator + Ceph Block/FS Storage  

---

## 1. Local Storage Limitations

Relying on Local Path provisioning or HostPath NVMe RAID (`25-storage-io-optimization.md`) bounds a Pod's data to a single physical node. In a multi-node GPU cluster:
- If Node A downloads a 30GB model, Node B cannot access it.
- If a Pod fails over from Node A to Node B, it incurs a severe cold-start penalty to re-download the model.
- Time-Sliced replicas cannot easily share the same physical volume across network boundaries.

---

## 2. Distributed Storage with Rook/Ceph

To achieve true High Availability, the architecture employs **Ceph**, a highly scalable distributed storage system, orchestrated via the **Rook** Kubernetes operator. Ceph abstracts physical drives across all nodes into a unified virtual storage pool.

### CephFS for ReadWriteMany (RWX)

For HuggingFace Model Caching, we utilize **CephFS** (a POSIX-compliant filesystem). CephFS supports `ReadWriteMany`, allowing multiple Time-Sliced Pods across multiple physical nodes to concurrently mount and read the same model weights from a single shared network cache.

---

## 3. Deployment Configuration

### 3.1 Install Rook Operator

```bash
git clone --single-branch --branch v1.13.2 https://github.com/rook/rook.git
cd rook/deploy/examples

# Deploy core components
kubectl create -f crds.yaml -f common.yaml -f operator.yaml
```

### 3.2 Initialize the Ceph Cluster

Create a Ceph cluster consuming unformatted NVMe drives across the nodes.

```yaml
# cluster.yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  dataDirHostPath: /var/lib/rook
  storage:
    useAllNodes: true
    useAllDevices: true
    deviceFilter: "^nvme"
```
```bash
kubectl create -f cluster.yaml
```

---

## 4. Provisioning the Shared Model Cache

Once the Ceph cluster is healthy, provision the CephFS filesystem and the associated `StorageClass`.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-cephfs
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: rook-ceph
  fsName: shared-model-fs
  pool: shared-model-fs-data0
reclaimPolicy: Retain
allowVolumeExpansion: true
```

Update your workload manifests to request the distributed storage class:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hf-cache-pvc
spec:
  accessModes:
  - ReadWriteMany
  storageClassName: rook-cephfs
  resources:
    requests:
      storage: 500Gi
```

**Result:** A 500GB highly-available volume is mounted to `/root/.cache/huggingface` in all Time-Sliced inference pods, regardless of their host node.

---

## Next Steps

Proceed to `28-service-mesh-istio.md` to secure inter-node traffic with mTLS.
