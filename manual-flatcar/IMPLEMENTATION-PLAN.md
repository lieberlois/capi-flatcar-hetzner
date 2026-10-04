# Flatcar + Hetzner + Cluster API — Setup Guide

> Dieses Dokument ist ein **Ende-zu-Ende Setup-Guide**: Es bringt dich von einem
> leeren Verzeichnis zu einem laufenden Kubernetes-Cluster auf **Hetzner Cloud**
> mit **Flatcar Container Linux**, provisioniert über **Cluster API** (CAPI) mit
> dem **Cluster API Provider Hetzner** (CAPH) und **Ignition**-Bootstrap.
>
> Jede Zeile hier wurde in dieser Session real ausgeführt und verifiziert.
> Zielkonfiguration: 1 Control-Plane + 3 Worker (cpx22), Kubernetes **v1.36.4**,
> Flatcar **4593.2.5 stable**, CNI Cilium.

---

## 1. Zielarchitektur

```
[Lokal: kind-Cluster "capi-management"]
    ├─ CAPI Controllers (cluster-api v1.14.0)
    ├─ Kubeadm Bootstrap / Control-Plane (CAPBK)
    └─ CAPH (Infrastructure Hetzner v1.1.8)
            │  provisioniert via Hetzner Cloud API
            ▼
[Hetzner Cloud (dein Projekt)]
    ├─ LoadBalancer "hetzner-cluster-kube-apiserver-*"   ← API-Endpoint (LB, fsn1)
    ├─ Netzwerk "hetzner-cluster" (10.0.0.0/16, Subnetz 10.0.0.0/24)
    ├─ Control-Plane Node: cpx22, Flatcar 4593.2.5 stable
    └─ Worker Nodes (3x):  cpx22, Flatcar 4593.2.5 stable
```

> **Kubernetes-Binaries:** nicht mehr im Snapshot, sondern als offizielle
> `kubernetes-v1.36.4-x86-64.raw` aus der
> [sysext-bakery](https://github.com/flatcar/sysext-bakery). Ignition lädt sie
> beim Provisioning nach `/opt/extensions/` und verlinkt
> `/etc/extensions/kubernetes.raw`; `systemd-sysext` merged sie nach `/usr`.

**Glossar**
- **CAPI**  = Cluster API (Kubernetes SIG)
- **CAPH**  = Cluster API Provider Hetzner (`syself/cluster-api-provider-hetzner`)
- **CAPBK** = Kubeadm Bootstrap Provider (rendert Bootstrap-Daten)
- **Ignition** = Flatcar-Format, in dem CAPBK die Bootstrap-Daten ausliefert
- **CCM**   = hcloud Cloud Controller Manager (providerID, Labels, LB-Services)

---

## 2. Voraussetzungen (getestet)

| Tool        | Version | Hinweis |
|-------------|---------|---------|
| kind        | v0.30.0 | Management-Cluster lokal |
| clusterctl  | v1.12.2 | CAPI CLI |
| kubectl     | v1.34.3+ | |
| helm        | v4.0.4  | Cilium + hcloud-CCM |
| hcloud      | v1.57.0 | Hetzner CLI (nutzt `HCLOUD_TOKEN`) |
| packer      | aktuell | Flatcar-Snapshot bauen |
| ssh-keygen  | — | SSH-Key erzeugen |

> Alle Tools hier via Linuxbrew/Homebrew installiert. Du brauchst außerdem einen
> **Hetzner-API-Token** (Projekt-Token) und ein Hetzner-Konto mit einem frei
> nutzbaren Standort `fsn1`.

---

## 3. Schritt-für-Schritt

> **Konsistenz-Regel:** `HCLOUD_TOKEN` wird **immer als Environment-Variable**
> gesetzt, nie als hcloud-Context angelegt (`hcloud context create` ist
> interaktiv und dadurch für Skripte ungeeignet).

```bash
export HCLOUD_TOKEN="<dein-hetzner-token>"
```

### 3.1 Management-Cluster (kind) + CAPI initialisieren

```bash
# ⚠️ MUSS VOR kind create UND clusterctl init gesetzt sein (sonst kein Ignition!):
export EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION=true

kind create cluster --name capi-management --wait 5m
# → Context "kind-capi-management"

clusterctl init --core cluster-api --bootstrap kubeadm \
  --control-plane kubeadm --infrastructure hetzner
# → cluster-api v1.14.0, bootstrap-kubeadm v1.14.0,
#   control-plane-kubeadm v1.14.0, infrastructure-hetzner v1.1.8
#   Namespaces: capi-system, capbk-system, capi-kubeadm-control-plane-system, caph-system

kubectl get pods -A    # alle Controller abwarten (Ready)
```

### 3.2 Hetzner vorbereiten (SSH-Key + Snapshot)

```bash
# 1) Projektlokales SSH-Key-Pair:
ssh-keygen -t ed25519 -N "" -f .ssh/hetzner-flatcar-key -C capi-management-hetzner

# 2) Public-Key nach Hetzner hochladen:
hcloud ssh-key create --name hetzner-flatcar-key \
  --public-key-from-file .ssh/hetzner-flatcar-key.pub

# 3) Vanilla-Flatcar-Snapshot bauen (NUR x86 — ARM/cax11 ist nicht in fsn1 verfügbar):
#    Der Snapshot enthält KEINE Kubernetes-Binaries/Units; diese kommen beim
#    Provisioning per Ignition aus der upstream sysext-bakery (siehe §1/§3.3).
packer init .        # im Verzeichnis manual-flatcar/ (flatcar.pkr.hcl)
packer build .
# → Snapshot "flatcar-stable-x86", Flatcar 4593.2.5 stable

# 4) ⚠️ CAPH-Image-Label setzen — DER kritische Schritt!
#    CAPH v1.1.8 sucht per LABEL "caph-image-name" (Prefix "caph-",
#    NICHT caph.cluster.x-k8s.io/...). Snapshots haben keinen Namen.
SNAPSHOT_ID=$(HCLOUD_TOKEN=$HCLOUD_TOKEN hcloud image list -o json | \
  jq -r '.[] | select(.type=="snapshot") | .id')
curl -s -X PUT "https://api.hetzner.cloud/v1/images/$SNAPSHOT_ID" \
  -H "Authorization: Bearer $HCLOUD_TOKEN" -H "Content-Type: application/json" \
  -d '{"labels":{"caph-image-name":"flatcar-stable-x86","channel":"stable","os":"flatcar"}}'

# Verifikation (muss 1 ergeben):
curl -s "https://api.hetzner.cloud/v1/images?label_selector=caph-image-name%3D%3Dflatcar-stable-x86" \
  -H "Authorization: Bearer $HCLOUD_TOKEN" | jq '.meta.pagination.total_entries'
```

### 3.3 Secret + Manifeste applien

```bash
kubectl create secret generic hcloud -n default \
  --from-literal=hcloud="$HCLOUD_TOKEN" \
  --from-literal=robot-user='' --from-literal=robot-password=''

kubectl apply -f manifests/
```

**Manifeste (statisch, kein Helm-Chart):**

```
manifests/
├── cluster.yaml                 # Cluster (v1beta2) + controlPlaneRef/infrastructureRef
├── hcloud-cluster.yaml          # HetznerCluster (v1beta1) — Netzwerk, LB, Region, SSH-Keys
├── machine-template.yaml        # HCloudMachineTemplate CP
├── worker-machine-template.yaml # HCloudMachineTemplate Worker
├── control-plane.yaml           # KubeadmControlPlane (v1beta2, format: ignition)
└── worker-deployment.yaml       # KubeadmConfigTemplate + MachineDeployment (3 Replicas)
```

### 3.4 Warten + CNI + CCM

```bash
# Kubeconfig exportieren (in Repo, gitignored):
clusterctl get kubeconfig hetzner-cluster > hetzner-cluster.kubeconfig
export KUBECONFIG=$PWD/hetzner-cluster.kubeconfig

# Cilium (CNI) — kubeProxyReplacement MUSS false sein:
helm repo add cilium https://helm.cilium.io
helm install cilium cilium/cilium --version 1.18.4 --namespace kube-system \
  --set ipam.mode=kubernetes --set kubeProxyReplacement=false

# hcloud Cloud Controller Manager (setzt Instanz-Labels; kubelet läuft
# bereits mit cloud-provider=external aus kubeletExtraArgs):
helm repo add hcloud https://charts.hetzner.cloud
kubectl -n kube-system create secret generic hcloud-credentials \
  --from-literal=hcloud-token="$HCLOUD_TOKEN"
kubectl -n kube-system apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: hcloud-ccm-config
  namespace: kube-system
data:
  cloud-config: |
    token-location: /etc/hcloud/token
    network: hetzner-cluster
    private-network-only: false
EOF
helm install hccm hcloud/hcloud-cloud-controller-manager --namespace kube-system \
  --set secretName=hcloud-credentials --set secretKeyName=hcloud-token \
  --set cloudConfigName=hcloud-ccm-config

kubectl get nodes -o wide   # alle Nodes sollten Ready werden
```

### 3.5 Versionen upgraden (falls gewünscht)

KCP erlaubt pro Update nur **+1 Minor-Version** (z. B. v1.34 → v1.35 → v1.36).
Version + Binary-URLs in `control-plane.yaml` und `worker-deployment.yaml`
pflegen und `kubectl apply -f manifests/` ausführen — KCP macht den Rest
(Rolling Update der Machines).

---

## 4. Kritische Fallstricke (aus der Praxis, bitte lesen)

1. **`EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION=true`** muss VOR `kind create` und
   `clusterctl init` exportiert sein, sonst kein Ignition-Format.
2. **CAPH-Image-Label = `caph-image-name`**, nicht `caph.cluster.x-k8s.io/image-name`.
   CAPH v1.1.8 baut den Key aus `NameHetznerProviderPrefix = "caph-"` + `"image-name"`
   (Quelle: `api/v1beta1/tags.go`, Lookup: `pkg/services/hcloud/server/server.go:1987`).
   Ein falscher Label-Key resultiert in `no image found` trotz vorhandenem Snapshot.
3. **HCloudMachineTemplate ist immutable** → jede Änderung = Template löschen + neu
   anlegen. Achtung: bereits erzeugte Machines tragen die alte Config eingebettet —
   alte Machines löschen, damit KCP/MD sie neu bauen.
4. **SSH-Key `users:` Block** — Hetzner injiziert bei Custom-Snapshots keine Keys in
   Flatcar. Ohne `users.sshAuthorizedKeys` im `kubeadmConfigSpec` ist kein SSH-Debug.
5. **kubelet `cloud-provider=external`** nativ über `kubeletExtraArgs:` (v1beta2 →
   `name`/`value`-Liste) setzen, damit der hcloud-CCM providerID + Labels
   übernehmen kann. kubeadm schreibt das nach `/var/lib/kubelet/kubeadm-flags.env`,
   das die upstream `10-kubeadm.conf` der Sysext bereits einliest.
6. **Cilium**: `kubeProxyReplacement` muss explizit `false` sein, sonst scheitert die
   Helm-Inst-Validation an der ConfigMap.
7. **API-Gruppen**: Cluster/KCP/MD → `v1beta2`; CAPH → `v1beta1`.
   Refs nutzen `apiGroup:` + `kind:` + `name:` (NICHT `apiVersion`).
8. **Region `fsn1`** (nicht `fsn`); `spec.controlPlaneEndpoint: {host:"", port:443}`
   nötig, damit CAPH den LoadBalancer erstellt.

---

## 5. Troubleshooting-Checkliste

| Symptom | Ursache | Fix |
|---------|---------|-----|
| `no image found with name <ID>` | `imageName` war Snapshot-ID statt Label-Wert | `imageName: flatcar-stable-x86` + Label `caph-image-name` setzen |
| `no image found with name flatcar-stable-x86` trotz Label | Label-Key falsch | Label-Key `caph-image-name` verwenden (NICHT `caph.cluster.x-k8s.io/...`) |
| `HCloudMachineTemplate.Spec is immutable` | Spec nicht änderbar | löschen + neu anlegen, alte Machines neu bauen |
| `strict decoding error: ... apiVersion` | Refs mit `apiVersion` | `apiGroup:` statt `apiVersion` |
| `Unsupported value: "fsn"` | Location-Format falsch | `fsn1` |
| `waiting for control-plane endpoint` (Loop) | `spec.controlPlaneEndpoint` fehlt | `{host:"", port:443}` → LB wird erstellt |
| kind liefert kein Ignition | Flag nicht vor clusterctl init gesetzt | `export EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION=true` |
| Node `NotReady` / `cni plugin not initialized` | kein CNI | Cilium installieren (`kubeProxyReplacement=false`) |
| Node Ready, aber CAPI `Machine Ready=Unknown` | Node.providerID fehlt | CCM installieren + kubelet `--cloud-provider=external`; Notfall: `kubectl patch node ... -p '{"spec":{"providerID":"hcloud://<serverId>"}}'` |
| SSH `Permission denied` trotz Key in Hetzner | Flatcar bekommt Keys nicht injiziert | `users:` mit `sshAuthorizedKeys` im `kubeadmConfigSpec` |
| CP-Machine hängt in `Deleting` | alte Machine, CAPH-Finalizer | CAPH-Controller neu starten, ggf. Machine-Finalizer prüfen |

---

## 6. Aktueller Stand (nach Neubau, v1.36.4)

| Objekt | Status | Bemerkung |
|--------|--------|-----------|
| kind Cluster `capi-management` | ✔ Ready | Management-Cluster |
| CAPI/CAPH Provider | ✔ Ready | cluster-api/bk/cp v1.14.0, infra v1.1.8 |
| SSH-Key Hetzner | ✔ `hetzner-flatcar-key` | projektlokal `.ssh/hetzner-flatcar-key` |
| Flatcar Snapshot | ✔ `flatcar-stable-x86` | Label `caph-image-name` gesetzt |
| Netzwerk `hetzner-cluster` | ✔ | 10.0.0.0/16, Subnetz 10.0.0.0/24 |
| LoadBalancer (API) | ✔ | fsn1, Port 443 |
| Cluster CR | ✔ Provisioned, init=True | |
| Control-Plane | Neubau | `hetzner-control-plane-b44mg` (Server läuft) |
| Worker (3x) | Neubau | `hetzner-worker-md-xr7sf-*` (Server laufen) |
| Kubernetes | **v1.36.4** | upstream `kubernetes-v1.36.4-x86-64.raw` (sysext-bakery) |
| CNI | ✔ Cilium 1.18.4 | neu installiert nach Neubau (helm, Abschnitt 3.4) |
| CCM | ✔ hcloud-cloud-controller-manager | installiert; setzt providerID + Labels (kubelet läuft mit `--cloud-provider=external`) |
| Nodes | ✔ alle Ready | 1 CP + 3 Worker, v1.36.4 |
| Kubeconfig | ✔ `hetzner-cluster.kubeconfig` | im Repo-Root, gitignored |

> Nach einem vollständigen Cluster-Neubau (Löschen aller CAPI-Objekte) müssen
> CNI + CCM (Abschnitt 3.4) im frischen Workload-Cluster neu installiert werden,
> da diese innerhalb des Workload-Clusters laufen. Nach Neuinstallation werden
> alle Nodes `Ready` (inkl. korrekter providerID durch den CCM — kein manuelles
> Patch mehr nötig). Scale-Down/Up über das MachineDeployment (replicas) wird von
> CAPI mit Drain/Cordon ausgeführt — die Nodes zeigen dabei kurzfristig
> `Ready,SchedulingDisabled`.

---

## 7. Aufgeräumt / Bekanntes

- Packer-Template ist auf **x86** reduziert (ARM/cax11 existiert nicht in `fsn1`).
- `backups/` und `scripts/` sind Platzhalter (leer).
- `.gitignore` ignoriert `.ssh/`, `*.kubeconfig`, `.env` — Tokens und Keys landen
  nie im Repo.

---

## 8. Further Outlook — Automatische OS-Updates mit kured (und CAPI-Vereinbarkeit)

Flatcar aktualisiert sich standardmäßig **selbst** (update-engine, Kanal `stable`,
in-place, inkl. eigenständigem Reboot). Für einen von CAPI verwalteten Cluster ist
das unkontrollierte Rebooten unerwünscht. Zwei saubere Optionen:

**Option A (empfohlen): update-engine aktiv + kured für sichere Reboots**
- `update-engine` bleibt aktiv und lädt/staged OS-Updates (stable-Kanal).
- **kured** (DaemonSet im Workload-Cluster, CNCF Sandbox) überwacht den
  Reboot-Sentinel, nimmt einen **cluster-weiten Lock** (nur 1 Node rebootet
  gleichzeitig), **cordons + drains** den Node, rebootet und uncordont danach.
- Die Kubernetes-Binaries liegen in der upstream sysext-bakery-Erweiterung
  (`/opt/extensions/kubernetes/…raw`, per Ignition geladen) und werden von
  Flatcars `systemd-sysext` nach `/usr` gemerged → Node kommt nach dem Reboot
  sauber in den Cluster zurück.
- Einrichtung: `helm install kured kubereboot/kured` (bzw. Helm-Repo) mit
  `--set` auf Sentinel, Fenster (`--start-time/--end-time`), und Control-Plane-
  Tolerations.

**Option B: Auto-Update abschalten, OS-Version über Snapshot rollen**
- `update-engine` + `locksmithd` im Ignition maskieren (`systemctl mask ...`).
- Neuen Flatcar-Snapshot mit Zielversion per `packer build` bauen (gleiches Label),
  `HCloudMachineTemplate` neu anlegen (immutable → löschen+neu), KCP/MD rollen.
- Deterministisch, aber manueller — kein automatischer Patch-Flow.

**Vereinbarkeit kured ↔ Cluster API:**
- kured läuft **im Workload-Cluster** (wie Cilium/CCM) — das Management-Cluster und
  die CAPI-Controller sind davon unberührt.
- Ein Reboot **ändert die Machine-Identität nicht**: Die Node kommt mit derselben
  `providerID` zurück, kubelet registriert sich neu — CAPI sieht die Machine
  kurzzeitig `NotReady`, danach wieder `Ready`. **Kein Machine-Recreate**, kein
  Konflikt mit KCP/MD-Reconciles.
- **Achtung:** `MachineHealthCheck`/KCP-Health-Checks melden während eines Reboots
  kurz `NotHealthy`/etcd-Timeouts. Reboot-Fenster + großzügige `nodeStartupTimeout`
  setzen, damit CAPI den Reboot nicht als Unhealthy remediert (sonst Deleting+Neubau).
- Control-Plane-Nodes brauchen kured-Tolerations (`node-role.kubernetes.io/control-plane`)
  und ggf. `--drain-grace-period` — sonst werden CP-Nodes nicht getoucht.
- Nach einem **Cluster-Neubau** muss kured (wie Cilium/CCM, Abschnitt 3.4) neu
  installiert werden.
- OS-Version-Drift: kured aktualisiert die **OS-Patch-Level** in-place. Die
  **Kubernetes-Version** bleibt davon unabhängig über die Manifeste
  (Binaries pinning in `preKubeadmCommands` + `spec.version`) gesteuert.
- Für **Major-OS-Upgrades** (z. B. Flatcar-Channel-/Milestone-Wechsel) ist
  weiterhin Option B (Snapshot + CAPI-Rolling) der saubere Weg.