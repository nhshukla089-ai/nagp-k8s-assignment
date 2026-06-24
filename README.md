# Records API on Kubernetes

Small two-tier app for the K8s workshop submission — FastAPI on the front, Postgres in the back. API talks to the DB over cluster DNS, not pod IPs.

## Links

Fill these in once everything is deployed:

| | URL |
|---|---|
| Repo | `https://github.com/nhshukla089-ai/nagp-k8s-assignment` |
| Docker Hub | `https://hub.docker.com/r/YOUR_DOCKERHUB_USERNAME/nagp-api` |
| Live API | `http://<INGRESS_IP>/api/records` |
| Direct LB API | `http://<EXTERNAL-IP>/api/records` |
| Video walkthrough | `<paste link here>` |
| Write-up | [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md) |

## How it's wired

```
Browser → Ingress → nagp-api-service → 4 API pods
                                          ↓
                               postgres-service → 1 DB pod + disk
```

- DB host/port/user come from a ConfigMap — no hardcoding in `app.py`
- Password lives in a Secret (created with kubectl, not checked into git)
- Ingress is the primary Kubernetes exposure path
- A LoadBalancer Service is included so you can show an external IP on Minikube with `minikube tunnel`
- HPA bumps API pods from 4 to 8 when CPU/memory goes up

## Repo layout

```
api/              app code + Dockerfile
k8s/api/          API deployment, service, ingress, HPA
k8s/database/     Postgres + PVC + seed data
scripts/          build + deploy helpers
docs/             setup notes and submission doc
```

## Before you start

Install these if you don't have them already:

- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Docker Desktop](https://docs.docker.com/get-docker/)
- Docker Hub account
- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [Ingress addon guide](https://minikube.sigs.k8s.io/docs/handbook/addons/ingress/)

## Deploy

**1. Push the image**

```bash
docker login
chmod +x scripts/build-and-push.sh
./scripts/build-and-push.sh YOUR_DOCKERHUB_USERNAME 1.0.0
```

Edit `k8s/api/03-deployment.yaml` and swap in your image name.

**2. Start Minikube**

```bash
minikube start --driver=docker --cpus=4 --memory=6g
minikube addons enable ingress
minikube addons enable metrics-server
```

**3. Apply manifests**

```bash
export DB_PASSWORD='pick-something-strong'
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

**4. Grab the endpoint**

Ingress will work after the addon is ready. If you want an external IP demo, start a tunnel in another terminal.

```bash
kubectl get ingress nagp-api-ingress -n nagp-assignment -w
minikube tunnel
kubectl get svc nagp-api-lb -n nagp-assignment -w
```

Then hit it:

```bash
curl http://<INGRESS_IP>/api/records
curl http://<INGRESS_IP>/health
curl http://<EXTERNAL-IP>/api/records
```

## Endpoints

| Path | What it does |
|------|----------------|
| `GET /` | Basic info |
| `GET /health` | Probe endpoint |
| `GET /api/records` | Returns rows from Postgres |

## Recording the demo video

Rough order that worked for me:

```bash
# everything running
kubectl get all,ingress,hpa,pvc,configmap -n nagp-assignment

# fetch data
curl http://<INGRESS_IP>/api/records

# kill one API pod, watch it come back
kubectl get pods -n nagp-assignment -l app=nagp-api
kubectl delete pod <one-pod-name> -n nagp-assignment
kubectl get pods -n nagp-assignment -l app=nagp-api -w

# kill DB pod, data should still be there
kubectl delete pod -n nagp-assignment -l app=postgres
kubectl get pods -n nagp-assignment -l app=postgres -w
curl http://<INGRESS_IP>/api/records

# rolling update (bump image tag first)
kubectl apply -f k8s/api/03-deployment.yaml
kubectl rollout status deployment/nagp-api -n nagp-assignment

# HPA — run curl in a loop in another terminal
kubectl get hpa -n nagp-assignment -w

# FinOps bit
kubectl top pods -n nagp-assignment
kubectl describe deployment nagp-api -n nagp-assignment | grep -A5 "Limits\|Requests"
```

## Tear down when done

Minikube is local, but you should still clean up once you've recorded and submitted.

```bash
kubectl delete namespace nagp-assignment
minikube delete
```
