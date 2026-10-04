#!/usr/bin/env bash
# 05 — CAPI/CAPH-Manifeste applien.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl apply -f "$REPO_ROOT/manifests/"
