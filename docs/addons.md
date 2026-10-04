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

## Notes

- Sveltos replaces the previous manual `scripts/07-install-cilium.sh` and
  `scripts/08-install-ccm.sh` (removed).
- If GitOps is wanted later, Sveltos integrates with **Flux** sources
  (`kustomizationRefs` from a `GitRepository`), not Argo CD.
