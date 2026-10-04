# capi-flatcar-hetzner

Cluster API Provider Hetzner (CAPH) PoC: Kubernetes-Cluster auf Hetzner Cloud
mit **Flatcar Container Linux** (Ignition) und **Cluster API**.

## Status

- PoC abgeschlossen: 1 Control-Plane + Worker, Kubernetes **v1.36.3**
- Stack: CAPH (Hetzner), Cilium (CNI), hcloud-cloud-controller-manager
- Der PoC-Cluster wurde zwischenzeitlich gelöscht — die Manifeste und der
  Setup-Guide sind bereit für einen Neubau.

## Struktur

| Pfad                  | Inhalt                                             |
| --------------------- | -------------------------------------------------- |
| `IMPLEMENTATION-PLAN.md` | Ende-zu-Ende Setup-Guide (Phasen 3.1–3.5, Fallstricke, Troubleshooting, kured-Outlook) |
| `manifests/`          | Statische CAPI/CAPH/YAML-Manifeste (v1.36.3)       |
| `flatcar.pkr.hcl`     | Packer-Template: Flatcar-Snapshot für Hetzner (x86, stable) |
| `scripts/`            | Platzhalter                                        |
| `backups/`            | Platzhalter                                        |

## Quickstart (Zusammenfassung)

Alle Details inkl. Fallstricke stehen in `IMPLEMENTATION-PLAN.md`. Die Schritte:

1. `HCLOUD_TOKEN` setzen (Token mit Lesen+Schreiben, Projekt auswählen).
2. SSH-Key per `hcloud ssh-key create --public-key-from-file ...` hochladen.
3. `packer build flatcar.pkr.hcl` → Snapshot mit Label `caph-image-name=flatcar-stable-x86`.
4. kind-Management-Cluster mit `EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION=true`, `clusterctl init` mit CAPH.
5. `manifests/` applien, Kubeconfig exportieren.
6. Cilium + hcloud-CCM installieren (kubeProxyReplacement=false).

## Sensible Dateien

`.ssh/`, `*.kubeconfig` und `.env` sind in `.gitignore` — Tokens und Keys landen
nie im Repo.