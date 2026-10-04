#!/usr/bin/env bash
# 07 — Install Sveltos (addon controller) into the hub cluster, Mode 2
# (centralised agents: no Sveltos footprint in the managed clusters).
# Optional components not needed for this PoC are disabled (KISS).
set -euo pipefail

helm repo add projectsveltos https://projectsveltos.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install projectsveltos projectsveltos/projectsveltos \
  --namespace projectsveltos --create-namespace \
  --set agent.managementCluster=true \
  --set telemetry.disabled=true \
  --set accessManager.enabled=false \
  --set shardController.enabled=false \
  --set techsupportController.enabled=false \
  --set mcpServer.enabled=false

kubectl -n projectsveltos get pods
