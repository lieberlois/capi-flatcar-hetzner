# capi-flatcar-hetzner

Cluster API Provider Hetzner (CAPH) PoC: Kubernetes-Cluster auf Hetzner Cloud
mit **Flatcar Container Linux** (Ignition) und **Cluster API**.

Der Kubernetes-Stack kommt **nicht** aus manuell gebackenen Binaries oder
Systemd-Drop-Ins, sondern aus der offiziellen
[Flatcar `sysext-bakery`](https://github.com/flatcar/sysext-bakery)
`kubernetes-*.raw`-Erweiterung. Sie wird beim Provisioning per Ignition
geladen und von Flatcars `systemd-sysext` nach `/usr` gemerged.

## Status

- PoC: 1 Control-Plane + 3 Worker, Kubernetes **v1.36.4**
- Stack: CAPH (Hetzner), Cilium (CNI), hcloud-cloud-controller-manager
- Kubernetes-Binaries: upstream `kubernetes-v1.36.4-x86-64.raw` (sysext-bakery)
- Der PoC-Cluster wurde zwischenzeitlich gelöscht — die Manifeste, Scripts und
  der Setup-Guide sind bereit für einen Neubau.

## Struktur

| Pfad                     | Inhalt |
| ------------------------ | ------ |
| `IMPLEMENTATION-PLAN.md` | Ende-zu-Ende Setup-Guide (Phasen 3.1–3.5, Fallstricke, Troubleshooting, kured-Outlook) |
| `ROBUSTNESS-GUIDE.md`    | Fahrplan für einen robusten Long-Lived-Cluster |
| `manifests/`             | Statische CAPI/CAPH/YAML-Manifeste (v1.36.4) |
| `addons/`                | Sveltos `ClusterProfile`s (Cilium, hcloud-CCM) + Credential-Template |
| `flatcar.pkr.hcl`        | Packer-Template: **vanilla** Flatcar-Snapshot für Hetzner (x86, stable), Label `caph-image-name=flatcar-stable-x86` |
| `scripts/`               | Idempotente Setup-Scripts (kind, clusterctl, Snapshot, apply, Sveltos) |
| `../docs/`               | Architektur, Bootstrap-Schritte, Addon-Doku |

## Wie Kubernetes auf die Nodes kommt

1. Packer baut einen **vanilla** Flatcar-Snapshot (keine Binaries, keine Units).
2. Beim Provisioning liest Ignition die `kubeadmConfigSpec`:
   - `files:` schreibt nur noch Sysctl-Tuning und `resolv.conf`.
   - `ignition.containerLinuxConfig.additionalConfig` lädt per HTTP das
     offizielle `kubernetes-v1.36.4-x86-64.raw` nach
     `/opt/extensions/kubernetes/` und verlinkt `/etc/extensions/kubernetes.raw`.
   - Flatcars `systemd-sysext` merged daraus `/usr/bin/kubelet`,
     `/usr/bin/kubeadm`, `/usr/bin/kubectl`, CNI-Plugins und
     `/usr/lib/systemd/system/kubelet.service` nach `/usr`.
3. kubeadm startet mit nativen `kubeletExtraArgs:` (v1beta2-Liste):
   `cloud-provider=external`, `resolv-conf=/etc/kubernetes/resolv.conf`.

Kein `/opt/bin`, keine manuellen `kubelet.service`-Drop-Ins und keine
imperativen Bootstrap-Kommandos — alles deklarativ via Ignition.

## Quickstart (Zusammenfassung)

Alle Details inkl. Fallstricke stehen in `IMPLEMENTATION-PLAN.md`. Kurzfassung:

1. `.env` anlegen (`HCLOUD_TOKEN`) und `set -a && source .env && set +a`.
2. `scripts/01-init-kind.sh` — kind-Management-Cluster + `clusterctl init` (CAPH).
3. `scripts/02-init-ssh.sh` — Hetzner-SSH-Key hochladen.
4. `scripts/03-init-snapshot.sh` — Packer-Snapshot bauen + labeln.
5. `scripts/04-create-secret.sh` + `scripts/05-apply.sh`.
6. `scripts/06-get-creds.sh`.
7. Addons: `scripts/07-install-sveltos.sh` (Hub) und `scripts/08-apply-addons.sh` —
   Sveltos deployt Cilium + hcloud-CCM automatisch in alle Cluster mit Label
   `addons: enabled`.

## Sensible Dateien

`.ssh/`, `*.kubeconfig`, `.env` und private Keys sind in `.gitignore` — Tokens
und Keys landen nie im Repo.
