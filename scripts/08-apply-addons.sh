#!/usr/bin/env bash
# 08 — Register the addon ClusterProfiles with Sveltos.
#
# Imperative bootstrap (documented in docs/bootstrap.md): renders the hub
# ConfigMap that carries the workload hcloud credentials (token from .env,
# never committed) and applies the declarative ClusterProfiles.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDONS="$REPO_ROOT/addons"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN setzen (.env)}"

TOKEN_B64="$(printf '%s' "$HCLOUD_TOKEN" | base64 | tr -d '\n')"
sed "s|__HCLOUD_TOKEN_B64__|${TOKEN_B64}|" \
  "$ADDONS/hcloud-ccm-addon.configmap.yaml.tmpl" | kubectl apply -f -

kubectl apply -f "$ADDONS/clusterprofile-cilium.yaml"
kubectl apply -f "$ADDONS/clusterprofile-hcloud-ccm.yaml"

kubectl get clusterprofiles
