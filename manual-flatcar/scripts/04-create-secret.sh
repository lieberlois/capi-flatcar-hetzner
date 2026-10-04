#!/usr/bin/env bash
# 04 — CAPH-Hetzner-Secret im default-Namespace anlegen.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN setzen (.env)}"

kubectl create secret generic hcloud -n default \
  --from-literal=hcloud="$HCLOUD_TOKEN" \
  --from-literal=robot-user='' \
  --from-literal=robot-password='' \
  --dry-run=client -o yaml | kubectl apply -f -
