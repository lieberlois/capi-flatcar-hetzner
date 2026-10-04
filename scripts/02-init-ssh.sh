#!/usr/bin/env bash
# 02 — Projektlokales SSH-Keypair erzeugen und nach Hetzner hochladen.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN setzen (.env)}"

KEY="${1:-.ssh/hetzner-flatcar-key}"
if [ ! -f "$KEY" ]; then
  ssh-keygen -t ed25519 -N "" -f "$KEY" -C capi-management-hetzner
fi

if ! hcloud ssh-key describe hetzner-flatcar-key >/dev/null 2>&1; then
  hcloud ssh-key create --name hetzner-flatcar-key --public-key-from-file "$KEY.pub"
fi

hcloud ssh-key list -o columns=name,fingerprint
