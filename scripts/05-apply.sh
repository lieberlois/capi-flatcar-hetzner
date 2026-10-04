#!/usr/bin/env bash
# 05 — Render the Helm chart and apply the CAPI objects.
# Extra values can be passed through, e.g.:
#   scripts/05-apply.sh --set kubernetesVersion=v1.37.0
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

helm template capi "$REPO_ROOT/chart" "$@" | kubectl apply -f -
