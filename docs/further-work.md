# Further work

Deliberately out of scope for this PoC, but worth doing before production.

## Single-node / control-plane upgrade strategy

Upgrading Kubernetes on a **single-node** cluster (one control-plane node with
stacked etcd) needs care, because that node *is* the etcd quorum.

- **KCP's default rollout is a surge (`maxSurge: 1`).** On a version bump it
  creates a **second** control-plane Machine first; the new node joins the
  existing etcd member set and only then is the old node drained and removed. So
  a single-node upgrade preserves cluster state, at the cost of a temporary extra
  server. **Keep the surge** (`maxSurge: 1`); `maxSurge: 0` would be delete-first
  and risk losing etcd.
- Our **reprovision-only** strategy fits this: the surge node fetches the new
  sysext via Ignition and joins. If the surge fails, the old node stays (fails
  safe).

For the "no extra node" path, **Cluster API v1.12 (Jan 2026) added in-place
updates and chained upgrades** — exactly these primitives:

- **In-place updates:** update existing Machines without delete/recreate via an
  *update extension* (CAPI picks it only when the change doesn't require a
  drain/pod restart).
- **Chained upgrades:** CAPI sequences control plane → workers and can chain
  multiple upgrade steps to reach a target, skipping unneeded worker steps.
- Blog: <https://kubernetes.io/blog/2026/01/27/cluster-api-v1-12-release/>

Follow-ups:

- [ ] Adopt an in-place update extension so a single-node cluster can upgrade
      without a surge node — pair it with an **in-place sysext update**
      (`systemd-sysupdate` + a controlled reboot, or a rebuilt snapshot).
- [ ] Use **chained upgrades** to move across minors in one declarative change.
- [ ] Snapshot etcd (etcdctl / Velero) before upgrades; single-node stacked etcd
      has no redundancy if the node is lost.

See `IMPLEMENTATION-PLAN.md` §8 for the current (reprovision-only) strategy.

## Hosted control planes (HCP)

The single-node etcd fragility above largely disappears with **hosted control
planes**: the control plane (apiserver / etcd / scheduler / controller-manager)
runs as pods in a **hosting** cluster, and workload clusters contain only
**workers**.

This is a strong fit for this repo's node model:

- No etcd on the nodes → no stacked-etcd upgrade/data-loss concern.
- Workers are pure and disposable → the **reprovision-only** + Flatcar **sysext**
  bootstrap is exactly the right shape (upgrade = roll a new worker).
- The control plane is upgraded independently of the workers, and single-node
  workload clusters become trivial (one worker, no control plane on it).

Sketch of the change:

- Replace the `KubeadmControlPlane` half of `chart/` with an HCP provider —
  e.g. **Kamaji** (kubeadm-based) or **k0smotron** (k0s-based), both CAPI-compatible.
- Keep the worker side **unchanged**: `MachineDeployment` + `KubeadmConfigTemplate`
  + Flatcar Ignition/sysext, plus the **Sveltos** ClusterProfiles (Cilium/CCM).
- The hosting cluster becomes the HA-critical component (back it up; run it in the
  management cluster).

Note: the `cloud-provider=external` + CCM providerID bootstrap still applies, but
with HCP the CCM can often run **control-plane-side** rather than as a pod on a
CNI-less worker — which may remove the chicken-and-egg we hit here.

## Other

- **ClusterClass / managed topologies** (CAPH ships a ClusterClass) for
  templating many clusters from one definition — see `ROBUSTNESS-GUIDE.md` §B.
- **kured**-driven in-place OS/sysext updates — the alternative to masking
  `update-engine`/`locksmithd` (see `IMPLEMENTATION-PLAN.md` §8).
- **Observability** (Prometheus/Grafana, Cilium Hubble) and **etcd backups**.
- **Read-only Hetzner token** for the workload CCM (only the CAPH hub secret
  needs write access).
