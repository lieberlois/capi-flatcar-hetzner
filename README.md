# capi-flatcar-hetzner

**Kubernetes on [Flatcar Container Linux](https://www.flatcar.org/) in Hetzner
Cloud, provisioned with [Cluster API](https://cluster-api.sigs.k8s.io/) (CAPI).**

A small, reproducible **reference setup** — the point being that the Kubernetes
binaries are *not* baked into a custom image and addons are *not* installed by
hand:

- **Kubernetes comes from Flatcar.** `kubelet` / `kubeadm` / `kubectl` (and CNI
  plugins) are delivered as the upstream
  [`flatcar/sysext-bakery`](https://github.com/flatcar/sysext-bakery)
  `kubernetes-<version>.raw`, fetched by **Ignition** at provisioning time and
  merged into `/usr` by **`systemd-sysext`**. No custom-baked Kubernetes, no
  `/opt/bin`, no hand-written systemd drop-ins.
- **Infrastructure:** Hetzner Cloud via
  [CAPH](https://github.com/syself/cluster-api-provider-hetzner).
- **Addons are declarative:** **Cilium** (CNI) and the **hcloud CCM** are
  delivered by [Sveltos](https://projectsveltos.io/) from the management
  cluster — no manual `helm install` into workload clusters.
- **Clusters are a Helm chart:** a map of clusters in `chart/values.yaml`, with a
  per-cluster namespace and a per-role Kubernetes version (including
  control-plane-only **single-node** clusters).
- **Updates are reprovision-based:** Flatcar's self-update/reboot is masked; bump
  the version and CAPI rolls fresh nodes (KCP surge preserves etcd).

New here? Start with [`docs/`](docs/README.md): architecture, bootstrap, addons,
production notes, and further work.

## Status

PoC / reference implementation — **verified end-to-end**:

- provisions a Hetzner workload cluster **and** a control-plane-only
  **single-node** cluster (Flatcar, `cpx22`);
- **Cilium**, **kube-proxy**, and the **hcloud CCM** come up automatically via
  Sveltos (nodes `Ready`, `providerID` set);
- **upgrade tested** (`v1.36.5 → v1.37.1`) via KCP's surge rollout — etcd
  preserved;
- Kubernetes version: **`v1.37.1`** (from `kubernetes-v1.37.1-x86-64.raw`).

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
     official `kubernetes-v1.37.1-x86-64.raw` over HTTP to
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
