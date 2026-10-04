#!/usr/bin/env bash
# 03 — Build a vanilla Flatcar snapshot (Packer) and label it for CAPH.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${HCLOUD_TOKEN:?set HCLOUD_TOKEN (.env)}"

cd "$REPO_ROOT"
packer init .
packer build .

# CAPH looks up images by the label `caph-image-name`. Snapshots have no name,
# so set the label explicitly (idempotent).
SNAPSHOT_ID=$(hcloud image list -t snapshot -o json | jq -r 'sort_by(.created) | last | .id')
curl -fsS -X PUT "https://api.hetzner.cloud/v1/images/${SNAPSHOT_ID}" \
  -H "Authorization: Bearer ${HCLOUD_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"labels":{"caph-image-name":"flatcar-stable-x86","channel":"stable","os":"flatcar"}}' >/dev/null

echo "Snapshot ${SNAPSHOT_ID} labelled: caph-image-name=flatcar-stable-x86"
