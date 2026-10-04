# Architecture

Two layers: **node provisioning** (CAPI + Flatcar sysext) and **addon
delivery** (Sveltos). The hub is the `kind` cluster `capi-management`.

## CAPI resource graph

`Machine` is the hinge: it binds one bootstrap config to one infrastructure
machine.

```mermaid
flowchart TD
  subgraph core["Core — cluster.x-k8s.io"]
    Cluster["Cluster"]
    MD["MachineDeployment"]
    MS["MachineSet"]
    M["Machine"]
  end
  subgraph cpn["Control plane — controlplane.cluster.x-k8s.io"]
    KCP["KubeadmControlPlane"]
  end
  subgraph boot["Bootstrap — bootstrap.cluster.x-k8s.io"]
    KCT["KubeadmConfigTemplate"]
    KC["KubeadmConfig"]
    Secret["Secret: bootstrap data (Ignition)"]
  end

  Cluster -->|controlPlaneRef| KCP
  Cluster -->|infrastructureRef| IC["InfrastructureCluster (CAPH)"]
  KCP -->|machineTemplate.infrastructureRef| IM["InfrastructureMachine (CAPH)"]
  KCP -->|owns| M
  KCP -->|bootstrap| KC
  MD -->|template.bootstrap.configRef| KCT
  MD -->|template.infrastructureRef| IM
  MD -->|owns| MS
  MS -->|owns| M
  M -->|bootstrap.configRef| KC
  M -->|infrastructureRef| IM
  KCT -.->|renders| KC
  KC -.->|writes| Secret
```

Namespaces: `capi-system` (core), `capi-kubeadm-control-plane-system` (KCP),
`capi-kubeadm-bootstrap-system` (CABPK), `caph-system` (Hetzner).

## Addon delivery (Sveltos)

Sveltos runs in the hub and **auto-discovers CAPI clusters** — it creates a
`SveltosCluster` and reads the workload kubeconfig from the CAPI-managed
secret. It then matches `ClusterProfile.clusterSelector` against the CAPI
`Cluster` labels and pushes addons from the hub (push model, so it works
before the workload has a CNI).

```mermaid
flowchart TD
  subgraph hub["kind hub: capi-management"]
    CAPI["CAPI core"]
    CAPH["CAPH (Hetzner)"]
    Sveltos["Sveltos addon-controller (projectsveltos)"]
  end
  Cluster["Cluster CR + label addons: enabled"]
  CP1["ClusterProfile: cilium"]
  CP2["ClusterProfile: hcloud-ccm (dependsOn cilium)"]
  WL["Workload cluster (Flatcar + Hetzner)"]

  CAPI --> Cluster
  Cluster --> CAPH
  CAPH --> WL
  Cluster -->|Sveltos auto-registers| Sveltos
  Sveltos --> CP1 -->|Helm| WL
  Sveltos --> CP2 -->|Helm| WL
```

See `docs/addons.md` for the ClusterProfiles and `docs/bootstrap.md` for the
imperative bootstrap steps.
