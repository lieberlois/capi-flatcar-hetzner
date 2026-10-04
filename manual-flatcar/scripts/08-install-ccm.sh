#!/usr/bin/env bash
# 08 — hcloud Cloud Controller Manager im Workload-Cluster installieren.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export KUBECONFIG="$REPO_ROOT/manual-flatcar/hetzner-cluster.kubeconfig"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN setzen (.env)}"

helm repo add hcloud https://charts.hetzner.cloud >/dev/null 2>&1 || true
helm repo update >/dev/null

kubectl -n kube-system create secret generic hcloud-credentials \
  --from-literal=hcloud-token="$HCLOUD_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: hcloud-ccm-config
  namespace: kube-system
data:
  cloud-config: |
    token-location: /etc/hcloud/token
    network: hetzner-cluster
    private-network-only: false
EOF

helm upgrade --install hccm hcloud/hcloud-cloud-controller-manager \
  --namespace kube-system \
  --set secretName=hcloud-credentials \
  --set secretKeyName=hcloud-token \
  --set cloudConfigName=hcloud-ccm-config
