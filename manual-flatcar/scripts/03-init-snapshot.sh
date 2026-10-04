#!/usr/bin/env bash
# 03 — Vanilla-Flatcar-Snapshot bauen (Packer) und für CAPH labeln.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN setzen (.env)}"

cd "$REPO_ROOT/manual-flatcar"
packer init .
packer build .

# CAPH findet Images über das Label `caph-image-name`. Snapshots haben keinen
# Namen, daher das Label explizit setzen (idempotent).
SNAPSHOT_ID=$(hcloud image list -t snapshot -o json | jq -r 'sort_by(.created) | last | .id')
curl -fsS -X PUT "https://api.hetzner.cloud/v1/images/${SNAPSHOT_ID}" \
  -H "Authorization: Bearer ${HCLOUD_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"labels":{"caph-image-name":"flatcar-stable-x86","channel":"stable","os":"flatcar"}}' >/dev/null

echo "Snapshot ${SNAPSHOT_ID} gelabelt: caph-image-name=flatcar-stable-x86"
