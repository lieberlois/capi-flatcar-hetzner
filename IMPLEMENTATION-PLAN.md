# Flatcar + Hetzner + Cluster API — Setup Guide

> This document is an **end-to-end setup guide**: it takes you from an
> empty directory to a running Kubernetes cluster on **Hetzner Cloud**
> with **Flatcar Container Linux**, provisioned via **Cluster API** (CAPI) with
> the **Cluster API Provider Hetzner** (CAPH) and **Ignition** bootstrap.
>
> Every line here was actually executed and verified in this session.
> Target configuration: 1 control plane + 3 workers (cpx22), Kubernetes **v1.36.5**,
> Flatcar **4757.2.1 stable**, CNI Cilium (via Sveltos).

---

## 1. Target architecture

```
[Local: kind cluster "capi-management"]
    ├─ CAPI Controllers (cluster-api v1.14.0)
    ├─ Kubeadm Bootstrap / Control-Plane (CAPBK)
    └─ CAPH (Infrastructure Hetzner v1.1.8)
            │  provisions via Hetzner Cloud API
            ▼
[Hetzner Cloud (your project)]
    ├─ LoadBalancer "hetzner-cluster-kube-apiserver-*"   ← API endpoint (LB, fsn1)
    ├─ Network "hetzner-cluster" (10.0.0.0/16, subnet 10.0.0.0/24)
    ├─ Control-Plane Node: cpx22, Flatcar 4593.2.5 stable
    └─ Worker Nodes (3x):  cpx22, Flatcar 4593.2.5 stable
```

> **Kubernetes binaries:** no longer in the snapshot, but as the official
> `kubernetes-v1.36.5-x86-64.raw` from the
> [sysext-bakery](https://github.com/flatcar/sysext-bakery). Ignition loads them
> during provisioning into `/opt/extensions/` and symlinks
> `/etc/extensions/kubernetes.raw`; `systemd-sysext` merges them into `/usr`.

**Glossary**
- **CAPI**  = Cluster API (Kubernetes SIG)
- **CAPH**  = Cluster API Provider Hetzner (`syself/cluster-api-provider-hetzner`)
- **CAPBK** = Kubeadm Bootstrap Provider (renders bootstrap data)
- **Ignition** = Flatcar format in which CAPBK delivers the bootstrap data
- **CCM**   = hcloud Cloud Controller Manager (providerID, labels, LB services)

---

## 2. Prerequisites (tested)

| Tool        | Version | Note |
|-------------|---------|---------|
| kind        | v0.30.0 | local management cluster |
| clusterctl  | v1.12.2 | CAPI CLI |
| kubectl     | v1.34.3+ | |
| helm        | v4.0.4  | Cilium + hcloud-CCM |
| hcloud      | v1.57.0 | Hetzner CLI (uses `HCLOUD_TOKEN`) |
| packer      | current | build the Flatcar snapshot |
| ssh-keygen  | — | generate the SSH key |

> All tools here installed via Linuxbrew/Homebrew. You also need a
> **Hetzner API token** (project token) and a Hetzner account with a freely
> usable location `fsn1`.

---

## 3. Step by step

> **Consistency rule:** `HCLOUD_TOKEN` is **always set as an environment variable**,
> never created as an hcloud context (`hcloud context create` is
> interactive and therefore unsuitable for scripts).

```bash
export HCLOUD_TOKEN="<your-hetzner-token>"
```

### 3.1 Initialize the management cluster (kind) + CAPI

```bash
# ⚠️ MUST be set BEFORE kind create AND clusterctl init (otherwise no Ignition!):
export EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION=true

kind create cluster --name capi-management --wait 5m
# → context "kind-capi-management"

clusterctl init --core cluster-api --bootstrap kubeadm \
  --control-plane kubeadm --infrastructure hetzner
# → cluster-api v1.14.0, bootstrap-kubeadm v1.14.0,
#   control-plane-kubeadm v1.14.0, infrastructure-hetzner v1.1.8
#   Namespaces: capi-system, capbk-system, capi-kubeadm-control-plane-system, caph-system

kubectl get pods -A    # wait for all controllers (Ready)
```

### 3.2 Prepare Hetzner (SSH key + snapshot)

```bash
# 1) Project-local SSH key pair:
ssh-keygen -t ed25519 -N "" -f .ssh/hetzner-flatcar-key -C capi-management-hetzner

# 2) Upload the public key to Hetzner:
hcloud ssh-key create --name hetzner-flatcar-key \
  --public-key-from-file .ssh/hetzner-flatcar-key.pub

# 3) Build the vanilla Flatcar snapshot (x86 ONLY — ARM/cax11 is not available in fsn1):
#    The snapshot contains NO Kubernetes binaries/units; these come during
#    provisioning via Ignition from the upstream sysext-bakery (see §1/§3.3).
packer init .        # in the repo root (flatcar.pkr.hcl)
packer build .
# → snapshot "flatcar-stable-x86", Flatcar 4593.2.5 stable

# 4) ⚠️ Set the CAPH image label — THE critical step!
#    CAPH v1.1.8 looks up by LABEL "caph-image-name" (prefix "caph-",
#    NOT caph.cluster.x-k8s.io/...). Snapshots have no name.
SNAPSHOT_ID=$(HCLOUD_TOKEN=$HCLOUD_TOKEN hcloud image list -o json | \
  jq -r '.[] | select(.type=="snapshot") | .id')
curl -s -X PUT "https://api.hetzner.cloud/v1/images/$SNAPSHOT_ID" \
  -H "Authorization: Bearer $HCLOUD_TOKEN" -H "Content-Type: application/json" \
  -d '{"labels":{"caph-image-name":"flatcar-stable-x86","channel":"stable","os":"flatcar"}}'

# Verification (must yield 1):
curl -s "https://api.hetzner.cloud/v1/images?label_selector=caph-image-name%3D%3Dflatcar-stable-x86" \
  -H "Authorization: Bearer $HCLOUD_TOKEN" | jq '.meta.pagination.total_entries'
```

### 3.3 Secret + apply the Helm chart

```bash
kubectl create secret generic hcloud -n default \
  --from-literal=hcloud="$HCLOUD_TOKEN" \
  --from-literal=robot-user='' --from-literal=robot-password=''

bash scripts/05-apply.sh        # helm template chart | kubectl apply -f -
```

**Helm chart (`chart/`):** the Kubernetes version and all names are templated;
`values.yaml` holds a map of clusters.

```
chart/
├── Chart.yaml
├── values.yaml                  # per-cluster namespace + per-role kubernetesVersion (clusters: map)
└── templates/
    ├── cluster.yaml             # Cluster + HetznerCluster
    ├── control-plane.yaml       # HCloudMachineTemplate (CP) + KubeadmControlPlane
    └── workers.yaml             # HCloudMachineTemplate (worker) + KubeadmConfigTemplate + MachineDeployment
```

### 3.4 Addons: Sveltos (Cilium + hcloud-CCM)

CNI and CCM are distributed **declaratively** by **Sveltos** in the hub cluster to all
workload clusters with the label `addons: enabled` — no manual
`helm install` into the workload cluster. Details: `docs/addons.md`.

```bash
# Install Sveltos in the hub (Mode 2, no agent in the workload):
bash scripts/07-install-sveltos.sh

# Render the credentials ConfigMap (from .env) + apply the ClusterProfiles:
bash scripts/08-apply-addons.sh

# Status:
kubectl get clusterprofiles,sveltoscluster,clustersummary -A
sveltosctl show addons            # optional

# Check the workload:
clusterctl get kubeconfig hetzner-cluster > hetzner-cluster.kubeconfig
KUBECONFIG=$PWD/hetzner-cluster.kubeconfig kubectl get nodes -o wide
```

Sveltos deploys Cilium first and the hcloud-CCM afterwards (`dependsOn`) — the
nodes thereby become Ready without manual intervention.

### 3.5 Upgrading versions (if desired)

KCP allows only **+1 minor version** per update (e.g. v1.34 → v1.35 → v1.36).
Set `kubernetesVersion` in `chart/values.yaml` (the sysext URLs are derived from it)
and run `bash scripts/05-apply.sh` — KCP does the rest
(rolling update of the Machines).

---

## 4. Critical pitfalls (from practice, please read)

1. **`EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION=true`** must be exported BEFORE `kind create` and
   `clusterctl init`, otherwise no Ignition format.
2. **CAPH image label = `caph-image-name`**, not `caph.cluster.x-k8s.io/image-name`.
   CAPH v1.1.8 builds the key from `NameHetznerProviderPrefix = "caph-"` + `"image-name"`
   (source: `api/v1beta1/tags.go`, lookup: `pkg/services/hcloud/server/server.go:1987`).
   A wrong label key results in `no image found` despite an existing snapshot.
3. **HCloudMachineTemplate is immutable** → every change = delete the template + create it
   anew. Note: already-created Machines carry the old config embedded —
   delete the old Machines so that KCP/MD rebuilds them.
4. **SSH key `users:` block** — for custom snapshots, Hetzner injects no keys into
   Flatcar. Without `users.sshAuthorizedKeys` in the `kubeadmConfigSpec` there is no SSH debug.
5. **kubelet `cloud-provider=external`** set natively via `kubeletExtraArgs:` (v1beta2 →
   `name`/`value` list), so that the hcloud-CCM can take over providerID + labels.
   kubeadm writes this to `/var/lib/kubelet/kubeadm-flags.env`,
   which the upstream `10-kubeadm.conf` of the sysext already reads.
6. **Cilium**: `kubeProxyReplacement` must explicitly be `false`, otherwise the
   Helm install validation fails on the ConfigMap.
7. **API groups**: Cluster/KCP/MD → `v1beta2`; CAPH → `v1beta1`.
   Refs use `apiGroup:` + `kind:` + `name:` (NOT `apiVersion`).
8. **Region `fsn1`** (not `fsn`); `spec.controlPlaneEndpoint: {host:"", port:443}`
   is required so that CAPH creates the LoadBalancer.

---

## 5. Troubleshooting checklist

| Symptom | Cause | Fix |
|---------|---------|-----|
| `no image found with name <ID>` | `imageName` was the snapshot ID instead of the label value | set `imageName: flatcar-stable-x86` + label `caph-image-name` |
| `no image found with name flatcar-stable-x86` despite label | wrong label key | use label key `caph-image-name` (NOT `caph.cluster.x-k8s.io/...`) |
| `HCloudMachineTemplate.Spec is immutable` | spec not modifiable | delete + recreate, rebuild old Machines |
| `strict decoding error: ... apiVersion` | refs with `apiVersion` | `apiGroup:` instead of `apiVersion` |
| `Unsupported value: "fsn"` | wrong location format | `fsn1` |
| `waiting for control-plane endpoint` (loop) | `spec.controlPlaneEndpoint` missing | `{host:"", port:443}` → LB is created |
| kind does not deliver Ignition | flag not set before clusterctl init | `export EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION=true` |
| Node `NotReady` / `cni plugin not initialized` | no CNI | check Sveltos `ClusterProfile/cilium` (`kubeProxyReplacement=false`) |
| Node Ready, but CAPI `Machine Ready=Unknown` | Node.providerID missing | check Sveltos `ClusterProfile/hcloud-ccm` + kubelet `cloud-provider=external`; emergency: `kubectl patch node ... -p '{"spec":{"providerID":"hcloud://<serverId>"}}'` |
| SSH `Permission denied` despite key in Hetzner | Flatcar does not get keys injected | `users:` with `sshAuthorizedKeys` in the `kubeadmConfigSpec` |
| CP Machine stuck in `Deleting` | old Machine, CAPH finalizer | restart the CAPH controller, check the Machine finalizer if needed |

---

## 6. Current state (after rebuild, v1.36.5)

| Object | Status | Note |
|--------|--------|-----------|
| kind cluster `capi-management` | ✔ Ready | management cluster |
| CAPI/CAPH provider | ✔ Ready | cluster-api/bk/cp v1.14.0, infra v1.1.8 |
| SSH key Hetzner | ✔ `hetzner-flatcar-key` | project-local `.ssh/hetzner-flatcar-key` |
| Flatcar snapshot | ✔ `flatcar-stable-x86` | label `caph-image-name` set |
| Network `hetzner-cluster` | ✔ | 10.0.0.0/16, subnet 10.0.0.0/24 |
| LoadBalancer (API) | ✔ | fsn1, port 443 |
| Cluster CR | ✔ Provisioned, init=True | |
| Control plane | Rebuild | `hetzner-control-plane-b44mg` (server running) |
| Workers (3x) | Rebuild | `hetzner-worker-md-xr7sf-*` (servers running) |
| Kubernetes | **v1.36.5** | upstream `kubernetes-v1.36.5-x86-64.raw` (sysext-bakery) |
| CNI | ✔ Cilium 1.18.4 | via Sveltos `ClusterProfile/cilium` (section 3.4) |
| CCM | ✔ hcloud-cloud-controller-manager | via Sveltos `ClusterProfile/hcloud-ccm`; sets providerID + labels |
| Nodes | ✔ all Ready | 1 CP + 3 workers, v1.36.5 |
| Kubeconfig | ✔ `hetzner-cluster.kubeconfig` | in the repo root, gitignored |

> After a full cluster rebuild (deleting all CAPI objects), CNI + CCM (section 3.4)
> are installed automatically by Sveltos in the fresh workload cluster
> as soon as it carries the profile label `addons: enabled`. Afterwards
> all nodes become `Ready` (including the correct providerID via the CCM — no manual
> patch needed anymore). Scale-down/up via the MachineDeployment (replicas) is
> performed by CAPI with drain/cordon — the nodes briefly show
> `Ready,SchedulingDisabled` during this.

---

## 7. Cleaned up / known issues

- The Packer template is reduced to **x86** (ARM/cax11 does not exist in `fsn1`).
- `backups/` and `scripts/` are placeholders (empty).
- `.gitignore` ignores `.ssh/`, `*.kubeconfig`, `.env` — tokens and keys never end up
  in the repo.

---

## 8. Update strategy — reprovision-only (implemented)

Flatcar updates **itself** by default (update-engine, `stable` channel, in-place
incl. its own reboot). Uncontrolled reboots are undesirable for a CAPI-managed
cluster, so the chosen strategy is **reprovision-only**:

- The Helm chart's Ignition config **masks** `update-engine.service` and
  `locksmithd.service` — nodes never self-update or self-reboot.
- A worker `MachineHealthCheck` (plus KCP's built-in control-plane remediation)
  handles unhealthy nodes.
- **Kubernetes and OS updates are rolled by CAPI as new nodes**: bump
  `kubernetesVersion` in `chart/values.yaml` (or rebuild the Flatcar snapshot for
  an OS version change), re-apply, and KCP/MD replace the machines. New nodes
  fetch the matching sysext via Ignition.
- The unused `systemd-sysupdate` scaffolding (transfer config, service, timer) has
  been removed — it is not part of this strategy.

> **Alternative (not used here): kured.** Instead of masking, keep `update-engine`
> active and install **kured** (DaemonSet in the workload cluster) to coordinate
> reboots (cluster-wide lock, cordon/drain, one node at a time), with generous
> KCP/MHC `nodeStartupTimeout`s and control-plane tolerations. That gives automated
> in-place OS patch updates at the cost of more moving parts. Either way, moving to
> a new Flatcar milestone / Kubernetes minor stays a snapshot + CAPI rolling
> operation.
