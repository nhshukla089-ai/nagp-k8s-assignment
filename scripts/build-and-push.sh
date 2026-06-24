#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${1:-}" ]]; then
  echo "Usage: $0 <dockerhub-username> [tag]"
  echo "Example: $0 anshikashukla 1.0.0"
  exit 1
fi

USERNAME="$1"
TAG="${2:-1.0.0}"
IMAGE="${USERNAME}/nagp-api:${TAG}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Building ${IMAGE}"
docker build -t "$IMAGE" "$SCRIPT_DIR/../api"

echo "==> Pushing ${IMAGE}"
docker push "$IMAGE"

echo ""
echo "Update k8s/api/03-deployment.yaml image to: ${IMAGE}"
echo "Then run: kubectl apply -f k8s/api/03-deployment.yaml"
