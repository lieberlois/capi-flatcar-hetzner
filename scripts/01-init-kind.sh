#!/usr/bin/env bash
# 01 — Create the kind management cluster and initialise CAPI/CAPH.
set -euo pipefail

# MUST be set before kind create AND clusterctl init (otherwise no Ignition bootstrap).
export EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION=true

kind create cluster --name capi-management --wait 5m

clusterctl init --core cluster-api \
  --bootstrap kubeadm \
  --control-plane kubeadm \
  --infrastructure hetzner

kubectl get pods -A
