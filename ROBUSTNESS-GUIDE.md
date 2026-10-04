# Robustness Guide — Flatcar + Hetzner + CAPI

> **Status: proposals, ONLY PARTIALLY VERIFIED.** Unlike
> `IMPLEMENTATION-PLAN.md` (every line was actually executed), the steps
> here are a **roadmap** for a robust long-lived cluster. Every change
> should be validated in a fresh environment before use — especially the
> Helm values, MHC parameters and the ClusterClass conversion.

Goal: raise the PoC from "works once" to "failure-tolerant, maintainable,
reproducible". Order = priority:

| # | Phase | Why first |
|---|-------|--------------|
| A | Secrets/Security | most expensive failure case (token leak) |
| B | Centralize versions | already drifting today (v1.36.5 ×several) |
| C | Deterministic Packer | reproducibility + label consistency |
| D | Harden manifests | explicit, hygienic, self-healing |
| E | Decide on OS updates | biggest risk for long-lived clusters |
| F | Automation/CI | reduce sources of error |
| G | Backup/DR | not present at all yet |

---

## A. Secrets & Security

### A.1 Never put HCLOUD_TOKEN in shell history / inline

Today the token appears inline in the docs (`kubectl create secret ... --from-literal=hcloud="$HCLOUD_TOKEN"`) and thus ends up in the shell history and potentially in `/proc` dumps.

**Implement immediately:**
```bash
# .env (gitignored) instead of inline export:
set -a && source .env && set +a

# Secret from a file instead of --from-literal:
printf '%s' "$HCLOUD_TOKEN" > /tmp/hcloud-token
kubectl create secret generic hcloud -n default \
  --from-file=hcloud=/tmp/hcloud-token \
  --from-file=robot-user=/dev/null \
  --from-file=robot-password=/dev/null
rm /tmp/hcloud-token
```

**Medium term:**
- Encrypt the token with GPG/gopass and decrypt it only at use (`export HCLOUD_TOKEN="$(gopass show hetzner/api-token)"`).
- Milestone PoC → production: manage CAPI secrets not by hand but via the **External Secrets Operator** (Hetzner secret not as an external provider — instead e.g. SOPS with age/cloud KMS for the `hcloud` secret and the workload secrets).

### A.2 SSH keys
- One project-wide key is in both templates. Optional: **separate key per node pool** (CP vs. workers), so that a leak does not immediately expose the whole cluster.
- Check whether root SSH is even necessary (debug access). Can keys later be removed from the templates via `users:` and injected only for emergencies?

---

## B. Versions: one source, no duplicates

The Kubernetes version used to be distributed several times (`spec.version` + the Ignition sysext URLs) and would drift. It is now centralized in the Helm chart: each cluster sets `kubernetesVersion`, overridable per role (`controlPlane.kubernetesVersion` / `workers.kubernetesVersion`), and it is templated into `spec.version` **and** the Ignition sysext URLs. `chart/values.yaml` is the single place; no drift.

### B.1 Done: Helm chart (this repo)
`chart/` is a Helm chart. `chart/values.yaml` holds a map of clusters; the
Kubernetes version is set per cluster and can be overridden per role
(`controlPlane` / `workers`). It is templated into `spec.version` and the
Ignition sysext URLs, and all names/machine types/replicas/network too.
Apply with `bash scripts/05-apply.sh` (which runs `helm template`).

### B.2 (Optional, future) ClusterClass + managed topologies
For a large fleet you can additionally move to Cluster API's managed topologies
(ClusterClass + `Cluster.spec.topology`); CAPH ships a ClusterClass template.
The Helm chart already covers the common case and is simpler.

### B.3 Kubernetes binaries: sysext instead of baking
Today the upstream **sysext-bakery** delivers the binaries via `kubernetes-v1.36.5-x86-64.raw` (kubelet/kubeadm/kubectl + CNI plugins). Ignition loads the `.raw` during provisioning; `systemd-sysext` merges it into `/usr`. Cluster construction thus depends on `extensions.flatcar.org`.

**Option 1 (immediate, cheap):** pin the version (currently `v1.36.5`) and use the sysupdate conf from the bakery (`systemd-sysupdate.timer`) so that patch levels within the same minor version are pulled in automatically. The sysupdate conf has `Verify=false` upstream — plan your own verification/signatures for production.

**Option 2 (better, long term):** mirror the `.raw` into an internal mirror/registry (Harbor/OCI) and sign it; nodes then fetch from your own mirror instead of directly from GitHub/flatcar.org.

---

## C. Deterministic Packer

### C.1 Derive the label from a variable (bugfix)
```hcl
snapshot_labels = {
  os              = "flatcar"
  channel         = var.channel
  caph-image-name = "flatcar-${var.channel}-x86"   # instead of hardcoded "stable"
}
```
Otherwise a `-var channel=beta` build creates a snapshot with the wrong `caph-image-name` label and CAPH does not find "flatcar-stable-x86".

### C.2 Pin the release instead of letting `stable` float
`flatcar-install -C stable` fetches the **current** stable version at build time. For reproducible builds, pin the tested version (e.g. `4593.2.5`) as soon as the `flatcar-install` CLI supports it (check the `--version` flag; possibly `-V 4593.2.5`). Document the result.

**Important:** Pinning in the snapshot alone is not enough — Flatcar updates itself at runtime (update-engine). See phase E.

### C.3 Verify the flatcar-install script
The script is fetched from GitHub via `curl`. At minimum:
- `curl --fail --proto '=https' --tlsv1.2`
- optional GPG verification (Flatcar signs release artifacts)

### C.4 Keep the docs in sync
After committing the label fix in `flatcar.pkr.hcl`, `IMPLEMENTATION-PLAN.md` §3.2 / §4.2 must be adjusted: the manual `curl` PUT step is dropped. Otherwise successors perform the step twice or believe the label must be set manually.

---

## D. Harden manifests

1. **Set `selector.matchLabels` explicitly** (today `null`, the template has `nodepool: worker`):
   ```yaml
   selector:
     matchLabels:
       nodepool: worker
   ```
2. **`replicas: 3`** in the MachineDeployment — the docs (1 CP + 3 workers) are the target configuration; as of now: 1.
3. **Add a MachineHealthCheck** so that broken nodes are remediated instead of left hanging:
   ```yaml
   apiVersion: cluster.x-k8s.io/v1beta2
   kind: MachineHealthCheck
   metadata:
     name: hetzner-worker-mhc
     namespace: default
   spec:
     clusterName: hetzner-cluster
     selector:
       matchLabels:
         nodepool: worker
     unhealthyConditions:
     - type: Ready
       status: Unknown
       timeout: 300s
     - type: Ready
       status: "False"
       timeout: 300s
     maxUnhealthy: 40%
     nodeStartupTimeout: 20m
   ```
   Note (interlinked with phase E): MHC/`KubeadmControlPlane` also remediates during planned reboots! Choose reboot windows + generous timeouts (see IMPLEMENTATION-PLAN §8).
4. **Extend `.gitignore`:**
   ```gitignore
   packer_cache/
   crash.*.log
   *.retry
   ```
5. **Be honest about empty placeholders:** `scripts/` and `backups/` do not exist but are listed in the README — either create them or remove the lines (or implement phases F/G directly).

---

## E. OS updates: make a decision (before long-lived!)

Flatcar reboots itself by default (update-engine, stable). In a CAPI cluster, uncontrolled rebooting is the biggest stability risk. The two options from `IMPLEMENTATION-PLAN.md` §8 made concrete:

### Option A (recommended): kured
```bash
helm repo add kubereboot https://kubereboot.github.io/charts
helm install kured kubereboot/kured --namespace kube-system \
  --set tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set tolerations[0].effect=NoSchedule \
  --set 'extraArgs.start-time=02:00' \
  --set 'extraArgs.end-time=04:00' \
  --set 'extraArgs.reboot-days=Su,Mo,Tu,We,Th' \
  --set 'extraArgs.drain-grace-period=300'
```
Accompanying measures (mandatory):
- MHC/KCP timeouts > max. reboot duration (see D.3, `nodeStartupTimeout: 20m`).
- Reinstall after every cluster rebuild (like Cilium/CCM).

### Option B: turn off auto-update (IMPLEMENTED)
The Helm chart masks `update-engine.service` and `locksmithd.service` via Ignition
(`systemd.units: mask: true`), so nodes never self-update or self-reboot.
Kubernetes and OS updates are rolled by CAPI as new nodes
(bump `kubernetesVersion` in `chart/values.yaml`, re-apply). Deterministic; no
automatic patch flow.

**Record the decision** (e.g. in README/plan §8) — the status quo (floating `stable` + self-reboot) is not viable for a managed cluster.

---

## F. Automation & CI

### F.1 Makefile/Taskfile for the documented phases
Goal: the manual steps from `IMPLEMENTATION-PLAN.md` §3 as idempotent targets. Example skeleton:

```make
.PHONY: image kind init apply cilium ccm verify env
env:
	@test -n "$$HCLOUD_TOKEN" || (echo "HCLOUD_TOKEN missing" && exit 1)

image: env
	packer init . && packer build .

kind: env
	EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION=true kind create cluster --name capi-management --wait 5m
	clusterctl init --core cluster-api --bootstrap kubeadm --control-plane kubeadm --infrastructure hetzner

apply: kind
	helm template capi chart | kubectl apply -f -

cilium:
	helm upgrade --install cilium cilium/cilium --version 1.18.4 -n kube-system \
	  --set ipam.mode=kubernetes --set kubeProxyReplacement=false

ccm:
	# hcloud-credentials Secret + ConfigMap + helm install hccm ...

verify:
	kubectl get nodes -o wide
	clusterctl describe cluster hetzner-cluster
```

### F.2 CI (GitHub Actions etc., lightweight)
```yaml
jobs:
  validate:
    steps:
      - run: packer validate flatcar.pkr.hcl
      - run: helm template capi chart | kubectl apply --dry-run=client -f -
      - run: yamllint chart/templates/
      - run: gitleaks detect --redact    # protection against token/key leaks
```
Pre-commit hook (optional): `pre-commit install` with gitleaks + yamllint + kubeconform.

---

## G. Backup & Disaster Recovery (use the `backups/` placeholder)

1. **Etcd snapshots of the control plane** (for 1 CP the only source of truth):
   - Via CronJob with `etcdctl snapshot save` (endpoint `/etc/kubernetes/pki/etcd` auth from Secret) or **Velero** incl. cluster API objects.
2. **CAPI object backup:** Qualifications: management cluster local (kind) — backups there are already "external", but the cluster is ephemeral. Manifests are in Git; missing: secrets (`hcloud`, bootstrap data). **Back up kubeconfig + secrets with SOPS**.
3. **Document a recovery playbook:** hypothetical scenarios (CP lost, management cluster gone, complete loss) → steps + expected time. This is completely missing.

---

## Quick checklist (work through by priority)

- [ ] Check `.ssh/` key separately per node pool; get token handling out of shell history (A)
- [ ] `flatcar.pkr.hcl`: label from `var.channel`; pin the release; update docs §3.2/§4.2 (C, B)
- [ ] Bootstrap configs: pin the version + use sysupdate (instead of snapshot baking); centralize versions or ClusterClass (B)
- [ ] MachineDeployment: `selector.matchLabels` + `replicas: 3`; MachineHealthCheck (D)
- [ ] Extend `.gitignore`; clean up README placeholders (D)
- [ ] Decide on the OS update strategy + implement kured (or mask) (E)
- [ ] Makefile + CI validation (packer validate, gitleaks) (F)
- [ ] etcd/Velero + recovery playbook (G)
