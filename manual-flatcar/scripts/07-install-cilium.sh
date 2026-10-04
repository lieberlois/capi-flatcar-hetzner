#!/usr/bin/env bash
# 07 — Cilium (CNI) im Workload-Cluster installieren.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export KUBECONFIG="$REPO_ROOT/manual-flatcar/hetzner-cluster.kubeconfig"

helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install cilium cilium/cilium --version 1.18.4 \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=false
