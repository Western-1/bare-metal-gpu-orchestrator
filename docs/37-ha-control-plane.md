# K3s High Availability Control Plane

**Component:** Kubernetes Master Nodes  
**Objective:** Mitigate single-point-of-failure in the orchestrator  
**Architecture:** External Datastore (PostgreSQL) + Quorum Masters  

---

## 1. Single-Node Vulnerability

The initial bootstrap architecture (`01-infrastructure-setup.md`) provisions k3s in a single-server topology utilizing an embedded SQLite datastore.

If the master node suffers a hardware failure (CPU panic, motherboard failure), the Kubernetes API Server, Scheduler, and Controller Manager terminate. While existing pods on worker nodes will continue to execute independently, the cluster becomes entirely unmanageable (no autoscaling, no deployments, no self-healing).

---

## 2. High Availability (HA) Architecture

To establish an Enterprise HA Control Plane, k3s must be decoupled from the local filesystem and scaled horizontally.

### Requirements
- **3 Master Nodes:** To establish quorum and tolerate 1 node failure.
- **External Datastore:** A highly available database (e.g., PostgreSQL or embedded etcd) to persist cluster state across the masters.
- **Fixed Registration Endpoint:** A load balancer (e.g., HAProxy or kube-vip) placed in front of the masters for agent (worker node) registration.

---

## 3. HA Deployment Protocol (External PostgreSQL)

This architecture utilizes an external PostgreSQL cluster (e.g., Patroni or cloud-managed RDS) as the Kine datastore for k3s.

### Step 1: Provision the Load Balancer

Configure HAProxy on an independent node (or via Keepalived/VRRP floating IP) to forward TCP/6443 to the backend master nodes.

```haproxy
# haproxy.cfg
frontend k8s-api
    bind *:6443
    mode tcp
    default_backend k8s-masters

backend k8s-masters
    mode tcp
    balance roundrobin
    server master1 10.0.0.11:6443 check
    server master2 10.0.0.12:6443 check
    server master3 10.0.0.13:6443 check
```

### Step 2: Bootstrap Server 1 (Initializer)

Install k3s on the first master, pointing it to the PostgreSQL datastore and defining the Load Balancer endpoint.

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --datastore-endpoint="postgres://k3s:password@postgres.internal.corp:5432/k3sdb" \
  --tls-san="loadbalancer.internal.corp"
```

### Step 3: Join Secondary Masters

Extract the `K3S_TOKEN` from Server 1 (`/var/lib/rancher/k3s/server/node-token`).
Join Server 2 and Server 3.

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN="<extracted-token>" sh -s - server \
  --datastore-endpoint="postgres://k3s:password@postgres.internal.corp:5432/k3sdb" \
  --tls-san="loadbalancer.internal.corp"
```

### Step 4: Join Worker Nodes

All GPU Worker nodes register exclusively via the highly available Load Balancer endpoint, ignorant of the individual master topologies.

```bash
curl -sfL https://get.k3s.io | K3S_URL=https://loadbalancer.internal.corp:6443 K3S_TOKEN="<extracted-token>" sh -
```

---

## Next Steps

Proceed to `38-finops-kubecost-chargeback.md` to establish cost attribution across tenants.
