# capi-flatcar-hetzner

Cluster API Provider Hetzner (CAPH) PoC: Kubernetes cluster on Hetzner Cloud
with **Flatcar Container Linux** (Ignition) and **Cluster API**.

The Kubernetes stack does **not** come from manually baked binaries or
systemd drop-ins, but from the official
[Flatcar `sysext-bakery`](https://github.com/flatcar/sysext-bakery)
`kubernetes-*.raw` extension. It is loaded during provisioning via Ignition
and merged into `/usr` by Flatcar's `systemd-sysext`.

## Status

- PoC: 1 control plane + 3 workers, Kubernetes **v1.36.5**
- Stack: CAPH (Hetzner), Cilium (CNI), hcloud-cloud-controller-manager
- Kubernetes binaries: upstream `kubernetes-v1.36.5-x86-64.raw` (sysext-bakery)
- The PoC cluster has since been deleted — the manifests, scripts and
  the setup guide are ready for a rebuild.

## Structure

| Path                     | Contents |
| ------------------------ | ------ |
| `IMPLEMENTATION-PLAN.md` | End-to-end setup guide (phases 3.1–3.5, pitfalls, troubleshooting, kured outlook) |
| `ROBUSTNESS-GUIDE.md`    | Roadmap for a robust long-lived cluster |
| `chart/`                 | Helm chart — per-cluster namespace, per-role Kubernetes version, all names templated; `values.yaml` is a map of clusters |
| `addons/`                | Sveltos `ClusterProfile`s (Cilium, hcloud-CCM) + credential template |
| `flatcar.pkr.hcl`        | Packer template: **vanilla** Flatcar snapshot for Hetzner (x86, stable), label `caph-image-name=flatcar-stable-x86` |
| `scripts/`               | Idempotent setup scripts (kind, clusterctl, snapshot, apply, Sveltos) |
| `docs/`                  | Architecture, bootstrap steps, addon docs (index: `docs/README.md`) |

## How Kubernetes gets onto the nodes

1. Packer builds a **vanilla** Flatcar snapshot (no binaries, no units).
2. During provisioning, Ignition reads the `kubeadmConfigSpec`:
   - A sysctl file (`/etc/sysctl.d/99-kubernetes.conf`) sets the Kubernetes
     networking prerequisites (`bridge-nf-call-iptables`, `ip_forward`).
   - `ignition.containerLinuxConfig.additionalConfig` loads the
     official `kubernetes-v1.36.5-x86-64.raw` over HTTP to
     `/opt/extensions/kubernetes/` and symlinks `/etc/extensions/kubernetes.raw`.
   - Flatcar's `systemd-sysext` merges `/usr/bin/kubelet`,
     `/usr/bin/kubeadm`, `/usr/bin/kubectl`, CNI plugins and
     `/usr/lib/systemd/system/kubelet.service` from it into `/usr`.
3. kubeadm starts with native `kubeletExtraArgs:` (v1beta2 list):
   `cloud-provider=external`.

No `/opt/bin`, no manual `kubelet.service` drop-ins and no
imperative bootstrap commands — everything declarative via Ignition.

**Updates (reprovision-only):** Flatcar's `update-engine` and `locksmithd` are
**masked** in Ignition, so nodes never self-update or self-reboot. Kubernetes and
OS updates are rolled by CAPI as **new nodes** — bump `kubernetesVersion` in
`chart/values.yaml` and re-apply. See `docs/production-notes.md`.

## Quickstart (summary)

All details including pitfalls are in `IMPLEMENTATION-PLAN.md`. Brief version:

1. Create `.env` (`HCLOUD_TOKEN`) and run `set -a && source .env && set +a`.
2. `scripts/01-init-kind.sh` — kind management cluster + `clusterctl init` (CAPH).
3. `scripts/02-init-ssh.sh` — upload the Hetzner SSH key.
4. `scripts/03-init-snapshot.sh` — build + label the Packer snapshot.
5. `scripts/04-create-secret.sh` + `scripts/05-apply.sh`.
6. `scripts/06-get-creds.sh`.
7. Addons: `scripts/07-install-sveltos.sh` (hub) and `scripts/08-apply-addons.sh` —
   Sveltos automatically deploys Cilium + hcloud-CCM into all clusters with the label
   `addons: enabled`.

## Sensitive files

`.ssh/`, `*.kubeconfig`, `.env` and private keys are in `.gitignore` — tokens
and keys never end up in the repo.
