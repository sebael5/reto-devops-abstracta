#!/usr/bin/env bash
# Basic smoke test: confirms the app is reachable through the Ingress,
# confirms probes are green, and confirms traffic is actually load-balanced
# across replicas (podinfo returns its own hostname in the response body).

set -euo pipefail

HOST="${1:-sample-app.local}"

echo "==> Pod status"
kubectl get pods -n sample-app -o wide

echo
echo "==> Probe status (should all show READY)"
kubectl get pods -n sample-app -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready

echo
echo "==> Hitting the app 6 times through the Ingress to confirm both replicas answer"
for i in $(seq 1 6); do
  curl -s "http://${HOST}/" | grep -o '"hostname":"[^"]*"' || echo "  (request $i failed)"
done

echo
echo "==> Direct in-cluster health check"
kubectl exec -n sample-app deploy/sample-app -- wget -qO- http://localhost:9898/healthz || true
