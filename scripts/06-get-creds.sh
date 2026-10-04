#!/usr/bin/env bash
# 06 — Workload-Kubeconfig exportieren (gitignored).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO_ROOT/hetzner-cluster.kubeconfig"

clusterctl get kubeconfig hetzner-cluster > "$OUT"
echo "Kubeconfig gespeichert: $OUT"
