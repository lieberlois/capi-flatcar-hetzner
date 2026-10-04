# Production notes — how this differs from a "typical" setup

This PoC deliberately stays small (single kind hub, a Helm chart, one
cluster). Here is what people usually change when they take this pattern
towards production. None of it is required to make the PoC work.

## Management plane

| PoC | Typical |
|---|---|
| `kind` hub on a laptop | A **dedicated, long-lived management cluster** (itself often CAPI-managed or at least backed up); the hub holds CAPI, CAPH and Sveltos |
| `clusterctl init` | **Cluster API Operator** (declarative provider lifecycle) |
| Providers upgraded by hand | CAPI/CAPH upgraded on a schedule with `clusterctl upgrade` / the operator |

The hub is the most critical component: if it dies you can't reconcile clusters.
Back it up (Velero + etcd snapshots) and treat it as production.

## Cluster definitions

| PoC | Typical |
|---|---|
| Static `KubeadmControlPlane` / `MachineDeployment` YAML | **ClusterClass + managed topologies** — one template, versioned, fanned out as `Cluster` objects |
| Kubernetes version hardcoded in several places | A single version parameter (ClusterClass variables / a render script) |
| Manual `kubectl apply` | Everything driven from Git (see below) |

ClusterClass is the single biggest "do differently": it removes the CP/worker
copy-paste and makes the sysext version a first-class variable.

## GitOps

We apply `ClusterProfile`s with `kubectl`. Most teams keep them in Git:

- **Sveltos + Flux**: Sveltos `kustomizationRefs` can source from a Flux
  `GitRepository`, so the profiles themselves are reconciled by Flux.
- GitOps controllers (Flux/Argo) also manage the hub's own addons.
- Note: Sveltos integrates with **Flux** sources; Argo CD is a separate path.

## Secrets

| PoC | Typical |
|---|---|
| `hcloud` secret created from `.env`; the CCM credential rendered into a hub ConfigMap by a script | **External Secrets Operator / SOPS+age / Vault** — no plaintext token anywhere, including the hub |
| One token | Scoped tokens/projects per environment; rotation |

## Addon lifecycle (Sveltos)

| PoC | Typical |
|---|---|
| `syncMode: Continuous` | `ContinuousWithDriftDetection` (reverts out-of-band changes; runs `drift-detection-manager`) |
| No health checks | `validateHealths` (Lua) to report addon health, plus Sveltos notifications (Slack/Teams/…) |
| All clusters updated at once | `maxUpdate` / progressive rollout / `tier`s to roll addon upgrades conservatively |
| All optional Sveltos controllers disabled | Some shop enable **access-manager** for multi-tenancy / per-team cluster access |
| Single addon set | Multiple profiles by cluster class (`env: prod`, `role: gpu`, …) |

## Supply chain

- Pin chart versions (we do) **and** verify signatures where available.
- Mirror charts/images into a private registry (Harbor/OCI) for air-gapped or
  rate-limited environments; use `registryCredentialsConfig` for private repos.
- Keep the same discipline for the Flatcar sysext `.raw` (upstream ships
  `Verify=false`; sign/mirror your own for production).

## Node / OS lifecycle

- `MachineHealthCheck`s for automatic remediation.
- **kured** to coordinate Flatcar OS + sysext reboots (see
  `ROBUSTNESS-GUIDE.md §E`), with generous KCP/MHC timeouts.
- Optionally enable `systemd-sysupdate.timer` for in-place patch updates.
- Cluster Autoscaler / node pools per workload.
- Observability: Prometheus/Grafana + Cilium Hubble; Sveltos itself exposes
  metrics and a Grafana dashboard.

## Scale

- Multiple `addon-controller` shards (**shard-controller**, which we disabled)
  once you manage many clusters.
- Sveltos **Mode 1** (per-cluster agent) vs **Mode 2** (central agent, what we
  use). Mode 2 keeps the workload clean; Mode 1 offloads work to the managed
  clusters. Pick per environment.

## Cilium specifics

We use the minimal working values (`ipam.mode=kubernetes`,
`kubeProxyReplacement=false`) because kube-proxy is deployed. Common production
choices: enable kube-proxy replacement (`kubeProxyReplacement=true` +
`k8sServiceHost`/`k8sServicePort` from the Cluster's control-plane endpoint),
native routing / BGP, encryption, and Hubble. Addon **upgrades** are done by
bumping `chartVersion` in the `ClusterProfile`; `syncMode: Continuous` lets
Sveltos roll the Helm release (verified working in this PoC).
