#!/usr/bin/env bash
# 06 — Export a workload kubeconfig (gitignored).
# Usage: scripts/06-get-creds.sh [cluster-name] [namespace]
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${1:-hetzner-cluster}"
NAMESPACE="${2:-default}"
OUT="$REPO_ROOT/${CLUSTER}.kubeconfig"

# NOTE: the namespace matters — e.g. the single-node example cluster lives in
# namespace "test-single-node": scripts/06-get-creds.sh test-single-node test-single-node
clusterctl get kubeconfig "$CLUSTER" -n "$NAMESPACE" > "$OUT"
echo "Kubeconfig written: $OUT"
