#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="nagp-assignment"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")/k8s"

if [[ -z "${DB_PASSWORD:-}" ]]; then
  echo "Set DB_PASSWORD before deploying, e.g.:"
  echo "  export DB_PASSWORD='your-strong-password'"
  exit 1
fi

echo "==> Creating namespace"
kubectl apply -f "$K8S_DIR/00-namespace.yaml"

echo "==> Creating secret"
kubectl create secret generic postgres-secret \
  --namespace "$NAMESPACE" \
  --from-literal=POSTGRES_PASSWORD="$DB_PASSWORD" \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Deploying database tier"
kubectl apply -f "$K8S_DIR/database/"

echo "==> Waiting for postgres to be ready"
kubectl wait --namespace "$NAMESPACE" \
  --for=condition=available deployment/postgres \
  --timeout=180s

echo "==> Deploying API tier"
kubectl apply -f "$K8S_DIR/api/"

echo "==> Waiting for API deployment"
kubectl wait --namespace "$NAMESPACE" \
  --for=condition=available deployment/nagp-api \
  --timeout=180s

echo ""
echo "Deployment complete."
echo ""
kubectl get all,ingress,hpa,pvc,configmap,secret -n "$NAMESPACE"
echo ""
echo "Ingress external IP (use minikube ingress addon + tunnel locally):"
kubectl get ingress nagp-api-ingress -n "$NAMESPACE"
echo ""
echo "Optional direct load balancer service for Minikube:"
kubectl get svc nagp-api-lb -n "$NAMESPACE" || true
