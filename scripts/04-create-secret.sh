#!/usr/bin/env bash
# 04 — Create the CAPH Hetzner Secret in the default namespace.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${HCLOUD_TOKEN:?set HCLOUD_TOKEN (.env)}"

kubectl create secret generic hcloud -n default \
  --from-literal=hcloud="$HCLOUD_TOKEN" \
  --from-literal=robot-user='' \
  --from-literal=robot-password='' \
  --dry-run=client -o yaml | kubectl apply -f -
