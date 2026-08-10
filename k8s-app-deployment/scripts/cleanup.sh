#!/usr/bin/env bash
# Tears down the kind cluster created by deploy.sh. Since everything (app,
# ingress controller, metrics-server) lives inside that one disposable
# cluster, deleting the cluster is sufficient cleanup -- no dangling
# cloud resources to worry about.

set -euo pipefail
CLUSTER_NAME="sample-app"

kind delete cluster --name "${CLUSTER_NAME}"
echo "==> Cluster '${CLUSTER_NAME}' deleted."
