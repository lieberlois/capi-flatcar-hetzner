#!/usr/bin/env bash
# 01 — Management-Cluster (kind) + CAPI/CAPH initialisieren.
set -euo pipefail

# ZWINGEND vor kind create UND clusterctl init (sonst kein Ignition-Bootstrap).
export EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION=true

kind create cluster --name capi-management --wait 5m

clusterctl init --core cluster-api \
  --bootstrap kubeadm \
  --control-plane kubeadm \
  --infrastructure hetzner

kubectl get pods -A
