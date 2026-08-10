#!/usr/bin/env bash
# Spins up a local kind cluster, installs ingress-nginx and metrics-server,
# then deploys the sample app via plain kubectl manifests.
#
# Usage:
#   ./scripts/deploy.sh

set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER_NAME="sample-app"

echo "==> Creating kind cluster (if it doesn't already exist)"
if ! kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  kind create cluster --name "${CLUSTER_NAME}" --config kind/kind-cluster-config.yaml
else
  echo "    cluster '${CLUSTER_NAME}' already exists, skipping"
fi

echo "==> Installing ingress-nginx (kind-specific manifest)"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
echo "==> Waiting for ingress-nginx controller to be ready"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

echo "==> Installing metrics-server (needed for the HPA to compute CPU %)"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# kind nodes use self-signed kubelet certs; metrics-server needs this patch
# to trust them (documented, well-known kind requirement, not a shortcut).
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' || true

echo "==> Deploying the app"
kubectl apply -f manifests/

echo "==> Waiting for the app to become available"
kubectl rollout status deployment/sample-app -n sample-app --timeout=120s

cat <<EOF

==> Done.
Add this to /etc/hosts to reach the app by hostname:
  127.0.0.1 sample-app.local

Then test with:
  curl http://sample-app.local/
or
  ./scripts/smoke-test.sh
EOF
