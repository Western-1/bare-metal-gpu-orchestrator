# Data Version Control (DVC)

**Component:** Dataset Lifecycle Management  
**Objective:** Version control terabyte-scale datasets without overwhelming Git  
**Architecture:** DVC + MinIO (S3) Backend  

---

## 1. The Dataset Versioning Problem

In traditional software engineering, Git meticulously tracks source code changes. However, Git is structurally incapable of tracking binary datasets, high-resolution image repositories, or multi-gigabyte Parquet files. If a Data Scientist pushes 50GB of training data to a Git repository, it immediately collapses the repository's performance.

If data is unversioned, model reproducibility is impossible. If a model trained today achieves 95% accuracy and a model trained next week achieves 80%, engineers must be able to instantly rollback to the exact state of the dataset used in the successful run.

---

## 2. Architecture: Git + DVC + MinIO

**Data Version Control (DVC)** resolves this by decoupling the metadata from the raw bytes.
1. The raw multi-gigabyte dataset is stored in the highly available S3-compatible object store (MinIO/Ceph).
2. DVC generates lightweight `.dvc` text files containing the cryptographic hashes (MD5) of the dataset.
3. Only these lightweight `.dvc` files are committed to Git.

---

## 3. Implementation Workflow

### 3.1 Initializing the DVC Repository

Within the machine learning monorepo, initialize DVC and point it to the local MinIO instance (`10-disaster-recovery.md`).

```bash
# Initialize DVC
dvc init

# Configure the remote storage backend (MinIO)
dvc remote add -d minio-backend s3://ml-datasets
dvc remote modify minio-backend endpointurl http://minio.data-plane.svc.cluster.local:9000
dvc remote modify minio-backend access_key_id ${MINIO_ACCESS_KEY}
dvc remote modify minio-backend secret_access_key ${MINIO_SECRET_KEY}
```

### 3.2 Tracking Data

When an engineer downloads or processes a new dataset, they track it via DVC rather than Git.

```bash
# Track a 50GB dataset folder
dvc add data/raw_images/

# DVC generates a data/raw_images.dvc file. Commit THIS to Git.
git add data/raw_images.dvc .gitignore
git commit -m "chore: Add initial raw image dataset for Vision model"

# Push the actual bytes to MinIO
dvc push
```

### 3.3 Reproducible CI/CD Fetching

When the KubeRay cluster executes a distributed training job, it does not clone a 50GB Git repository. Instead, it clones the lightweight Git repo and executes `dvc pull`. DVC inspects the Git commit, reads the correct MD5 hashes, and downloads the exact corresponding byte sequences from MinIO directly to the NVMe volumes.

```yaml
# CI/CD Training Pipeline Step
- name: Fetch Versioned Data
  run: |
    git checkout tags/v1.2.0
    dvc pull
```

---

## Next Steps

Proceed to `47-hyperparameter-tuning.md` to utilize this data in distributed optimization runs.
