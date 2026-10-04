# Addon delivery (Sveltos)

Addons (CNI + CCM) are delivered to workload clusters by **Sveltos**, running
in the hub (`projectsveltos` namespace), using declarative `ClusterProfile`
objects. No `helm install` is run against the workload cluster by hand.

## How a cluster opts in

A CAPI `Cluster` with the label `addons: enabled` is picked up by both
profiles:

```yaml
# manual-flatcar/manifests/cluster.yaml
metadata:
  labels:
    addons: enabled
```

## Profiles

| File | Poduces |
|---|---|
| `addons/clusterprofile-cilium.yaml` | Cilium 1.18.4 (`ipam.mode=kubernetes`, `kubeProxyReplacement=false`) |
| `addons/clusterprofile-hcloud-ccm.yaml` | hcloud CCM 1.38.0, `dependsOn: [cilium]` |

`dependsOn` guarantees Cilium is deployed before the CCM, so nodes can become
`Ready` first.

## Credentials

The hcloud CCM needs a `hcloud-credentials` Secret (and `hcloud-ccm-config`
ConfigMap) in the workload's `kube-system`. These are carried by a ConfigMap
`hcloud-ccm-addon` in the hub, whose data entries are the manifests to copy.
Sveltos `policyRefs` copies it into matching clusters.

The ConfigMap is **rendered at bootstrap** from `$HCLOUD_TOKEN`
(`scripts/08-apply-addons.sh`) — the token is never committed to git. See
`docs/bootstrap.md`.

## Components

Sveltos installs several controllers. This PoC disables the ones it does not
need (see `scripts/07-install-sveltos.sh`): `accessManager`,
`shardController`, `techsupportController`, `mcpServer`. Remaining:
`addon-controller` (core), `sc-manager` (registration), `classifier-manager`,
`hc-manager` (health checks), `event-manager`, and one `sveltos-agent` per
managed cluster (runs in the hub in Mode 2).

## Sveltos agents

Sveltos runs one `sveltos-agent` per registered cluster. In Mode 2 they all
live in the hub. Identify them by their labels (or `--cluster-name` args):

```bash
kubectl -n projectsveltos get deploy -l feature=sveltos-agent \
  -o custom-columns='AGENT:.metadata.name,CLUSTER:.metadata.labels.cluster-name,TYPE:.metadata.labels.cluster-type'
```

- `cluster-type=capi` → a CAPI workload cluster (e.g. `hetzner-cluster`).
- `cluster-type=sveltos` → a classically registered cluster; here the hub
  itself (`mgmt`), registered by the chart's `registerMgmtCluster` job.

CAPI clusters are tracked as CAPI clusters, not as `SveltosCluster` objects —
that is why `kubectl get sveltoscluster -A` only shows `mgmt`. Look at
`kubectl get clustersummary -A` (names ending `capi-<cluster>`) for their
provisioning status.

**Why does the hub itself have an agent?** Because the Helm chart self-registers
the hub as a managed cluster (the `registerMgmtCluster` job), so Sveltos treats
the hub like any other managed cluster and gives it an agent. It is **not**
required to manage the workload clusters — only to manage addons *on the hub*
and to run drift/health on it. To drop it, delete the `mgmt` SveltosCluster
(`kubectl delete sveltoscluster -n mgmt mgmt`). The chart has no `enabled`
toggle for self-registration, so a later `helm upgrade` may recreate it.

## Verify

```bash
# From the hub
kubectl get clusterprofiles
kubectl get sveltoscluster -A
kubectl get clustersummary -A            # per-cluster provisioning status

# Optional CLI
sveltosctl show addons

# From the workload
kubectl get pods -n kube-system | grep -E 'cilium|hcloud'
kubectl get nodes
```

## Sync / drift

`syncMode: Continuous` reconciles changes to the profiles. Switch to
`ContinuousWithDriftDetection` to also revert out-of-band changes (the agent
runs hub-side in Mode 2, so it works even before the workload has a CNI).

## Upgrades

Bump `chartVersion` in the `ClusterProfile` and re-apply it; `syncMode:
Continuous` makes Sveltos roll the Helm release on matching clusters. This was
verified in this PoC with a Cilium upgrade.

```bash
# edit addons/clusterprofile-cilium.yaml (chartVersion), then:
kubectl apply -f addons/clusterprofile-cilium.yaml
kubectl get clustersummary -A          # watch provisioning
```

For fleets, set `maxUpdate` / use `tier`s to roll out conservatively, and turn
on drift detection (`ContinuousWithDriftDetection`) + `validateHealths`.

## Further reading

- Sveltos — <https://projectsveltos.io/>
- "Projectsveltos with Hetzner Cloud and Cluster API" — <https://www.reddit.com/r/kubernetes/comments/zemvvo/projectsveltos_with_hetzner_cloud_and_clusterapi/>
- Full reference list: [README.md](README.md)

## Notes

- Sveltos replaces the previous manual `scripts/07-install-cilium.sh` and
  `scripts/08-install-ccm.sh` (removed).
- If GitOps is wanted later, Sveltos integrates with **Flux** sources
  (`kustomizationRefs` from a `GitRepository`), not Argo CD.
