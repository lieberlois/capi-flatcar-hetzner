# Bootstrap (imperative steps)

Everything here cannot be GitOps'd because it either creates the management
plane itself or supplies a secret. Everything **on the workload cluster**
(Cilium, hcloud CCM) is delivered by Sveltos, not by hand.

| # | Step | Why imperative |
|---|---|---|
| 1 | `kind create cluster --name capi-management` | Creates the hub |
| 2 | `clusterctl init --infrastructure hetzner` | Installs CAPI + CAPH into the hub |
| 3 | `packer build` (vanilla Flatcar snapshot) + label | Hetzner has no official Flatcar image; CAPH selects by `caph-image-name` |
| 4 | `bash scripts/07-install-sveltos.sh` | Installs the addon controller into the hub |
| 5 | `bash scripts/08-apply-addons.sh` | Renders the credential ConfigMap from `.env` and applies the ClusterProfiles |
| 6 | `bash scripts/05-apply.sh` | Renders the Helm chart (`chart/`) and creates the workload `Cluster` |

## Environment

```bash
cp .env.example .env      # then put HCLOUD_TOKEN in .env
set -a && source .env && set +a
export EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION=true   # before kind create / clusterctl init
```

## Order

```bash
bash scripts/01-init-kind.sh
bash scripts/02-init-ssh.sh
bash scripts/03-init-snapshot.sh
bash scripts/04-create-secret.sh
bash scripts/05-apply.sh          # creates Cluster (+ label addons=enabled)
bash scripts/07-install-sveltos.sh
bash scripts/08-apply-addons.sh   # Sveltos now installs Cilium + CCM
bash scripts/06-get-creds.sh
```

## Secrets

`08-apply-addons.sh` base64-encodes `$HCLOUD_TOKEN` into the hub ConfigMap
`hcloud-ccm-addon`; Sveltos copies the resulting workload Secret. The token
lives only in the hub (and the CAPH `hcloud` secret). For production, replace
this with SOPS/age or External Secrets Operator.
