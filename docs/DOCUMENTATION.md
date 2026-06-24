# Technical write-up

## What was asked

Build a two-tier app on Kubernetes — one service that hits a database over an API, containerized and pushed to Docker Hub.

| | API tier | DB tier |
|---|---|---|
| Reachable from outside | Yes (Ingress) | No |
| Pods | 4 | 1 |
| Rolling updates | Yes | No |
| Persistent disk | No | Yes |
| ConfigMap | Yes | Used for seed SQL |
| Secrets | Yes | Yes |

Other things to watch for: DB config shouldn't be baked into the app code, passwords shouldn't sit in plain text in yaml files, tiers should talk via service names not pod IPs, and we need CPU/memory limits plus some cost thinking (FinOps).

## What I assumed

- Running on **Minikube** because it avoids the GCE prepayment problem and was confirmed as acceptable in the class chat
- **FastAPI + Postgres** — Python is quick to wire up, Postgres has a solid official image and handles the init script thing cleanly
- One namespace (`nagp-assignment`) to keep everything grouped
- Minikube ingress addon for the primary public route
- Optional `LoadBalancer` service plus `minikube tunnel` if I want to show an external IP during the demo
- Default storage class for the PVC, so it works across clusters
- 8 rows in the seed data (spec said 5–10)
- Metrics server is on — enabled via Minikube addon; needed for HPA and `kubectl top`

## Architecture

```
Internet
   │
   ▼
Ingress  ──►  nagp-api-service  ──►  4 × API pods
                                         │
                                         │  postgres-service:5432
                                         ▼
                                    1 × Postgres pod
                                         │
                                         ▼
                                    PVC (2Gi)
```

The API reads `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` from the `api-config` ConfigMap. Password comes from `postgres-secret`, which I create at deploy time:

```bash
kubectl create secret generic postgres-secret \
  --namespace nagp-assignment \
  --from-literal=POSTGRES_PASSWORD='...' \
  --from-literal=DB_PASSWORD='...'
```

Same secret feeds both the Postgres container and the API — just different key names.

## Why these pieces

**API (FastAPI)**  
Connection pooling via `psycopg2.pool.ThreadedConnectionPool` (1–10 connections). Health checks on `/health` so Kubernetes can restart bad pods. Rolling update with `maxSurge: 1` / `maxUnavailable: 1` so there's always traffic capacity during deploys.

**Database**  
`postgres:16-alpine` — smaller image, does the job. Data lands on a PVC so deleting the pod doesn't wipe the table. Deployment uses `Recreate` strategy because it's a single replica with a ReadWriteOnce volume — RollingUpdate doesn't play nice with that setup.

Init SQL is a ConfigMap mounted into `/docker-entrypoint-initdb.d/`. Only runs when the data directory is empty, which is what we want.

**Networking**  
`postgres-service` is ClusterIP only. Ingress points at `nagp-api-service`. Nothing hits the DB from outside.
For Minikube, I can also use `nagp-api-lb` with `minikube tunnel` to demonstrate an external IP if I want to show the load balancer pattern explicitly.

## K8s objects

| Kind | Name |
|------|------|
| Namespace | nagp-assignment |
| ConfigMap | api-config, postgres-init-sql |
| Secret | postgres-secret |
| PVC | postgres-pvc |
| Deployment | nagp-api (×4), postgres (×1) |
| Service | nagp-api-service, postgres-service, nagp-api-lb |
| Ingress | nagp-api-ingress |
| HPA | nagp-api-hpa |

## Resource sizing

### API pods

| | Value | Why |
|---|---|---|
| CPU request | 50m | Mostly idle waiting on DB; `kubectl top` showed single digits at rest |
| CPU limit | 200m | Room for bursts |
| Memory request | 128Mi | ~90–100Mi in practice |
| Memory limit | 256Mi | Safety cap |
| Replicas | 4 | Spec |
| HPA max | 8 | Only scale up when actually loaded |

Checked with:

```bash
kubectl top pods -n nagp-assignment -l app=nagp-api
```

### Postgres pod

| | Value | Why |
|---|---|---|
| CPU request | 100m | Postgres wants a baseline even for tiny datasets |
| CPU limit | 250m | |
| Memory request | 256Mi | |
| Memory limit | 512Mi | |
| Disk | 2Gi | Way more than 8 rows need, but keeps it simple |

## FinOps — three things I looked at

### 1. Right-size requests instead of guessing high

Easy to slap `250m / 512Mi` on everything because "why not". But the scheduler reserves requests whether you use them or not. After checking `kubectl top`, I dropped API requests to `50m / 128Mi`. More pods fit on the same node.

### 2. HPA instead of always running max replicas

Spec needs 4 pods minimum. Running 8 all the time for a demo app is wasteful. HPA keeps 4 normally and only adds pods when CPU goes past 70% or memory past 80%. Scale-down waits 120s so it doesn't flap.

### 3. Cheaper storage and images

- 2Gi standard disk, not premium SSD — we're not doing heavy I/O
- `postgres:16-alpine` and `python:3.12-slim` — smaller pulls, less disk
- `Recreate` on DB avoids needing a multi-writer volume

Other ideas I didn't bother with for this scope: cluster autoscaler, tearing down the whole cluster after submission (which I'll do anyway).

### Metrics I actually looked at

| When | CPU | Memory | What I did |
|------|-----|--------|------------|
| API idle | ~5–15m | ~90Mi | Set requests to 50m / 128Mi |
| API under curl spam | ~80–120m | ~150Mi | Left limit at 200m, HPA handles the rest |
| Postgres idle | ~20–40m | ~150Mi | 100m / 256Mi requests |

## Deploy strategies

**API — RollingUpdate**  
One pod goes down, one comes up. With 4 replicas you never drop below 3 serving traffic during an image change.

**DB — Recreate**  
Single pod + one PVC. Kubernetes has to unmount the volume from the old pod before the new one can attach it. Recreate does that cleanly.

## Self-healing

| Kill what | What happens |
|-----------|--------------|
| API pod | Deployment spins up a replacement |
| DB pod | Same — new pod, same PVC, data intact |
| API pod that fails health check | Readiness probe pulls it from the service until it's good |

## Minikube demo flow

1. Start the cluster with the Docker driver.
2. Enable `ingress` and `metrics-server`.
3. Apply the manifests.
4. Use either:
   - Ingress for the Kubernetes-native route, or
   - `minikube tunnel` plus `nagp-api-lb` if I want to show an external IP.
5. Show pod deletion and recovery for API and DB.
6. Show the database data still present after DB pod replacement.

## References

- [Kubernetes docs](https://kubernetes.io/docs/home/)
- [Helm](https://helm.sh/) — didn't need it here but we touched on it in class
- [Minikube ingress addon](https://minikube.sigs.k8s.io/docs/handbook/addons/ingress/)
- [Minikube tunnel](https://minikube.sigs.k8s.io/docs/handbook/accessing/)
