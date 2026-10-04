# Documentation

| Doc | Contents |
|---|---|
| [architecture.md](architecture.md) | CAPI resource graph + Sveltos addon-delivery flow |
| [bootstrap.md](bootstrap.md) | The imperative bootstrap steps and why they can't be GitOps'd |
| [addons.md](addons.md) | Sveltos `ClusterProfile`s, agents, upgrades |
| [production-notes.md](production-notes.md) | How a production setup typically differs from this PoC |

The approved design for the Sveltos work lives in
[superpowers/specs/2026-10-04-sveltos-addons-design.md](superpowers/specs/2026-10-04-sveltos-addons-design.md).

## External references

**Flatcar / sysext**
- sysext-bakery — <https://github.com/flatcar/sysext-bakery>
- Flatcar Kubernetes guide — <https://www.flatcar.org/docs/latest/orchestrate/kubernetes/getting-started-with-kubernetes/>
- Flatcar Hetzner guide — <https://www.flatcar.org/docs/latest/deploy/cloud/hetzner/>

**Cluster API / CAPH**
- Cluster API book — <https://cluster-api.sigs.k8s.io/>
- CAPI + Ignition — <https://cluster-api.sigs.k8s.io/tasks/experimental-features/ignition>
- CAPH docs — <https://syself.com/docs/caph/>
- Hetzner community tutorial: Kubernetes with Cluster API — <https://community.hetzner.com/tutorials/kubernetes-on-hetzner-with-cluster-api/>

**Sveltos**
- Project docs — <https://projectsveltos.io/>
- Helm charts — <https://projectsveltos.github.io/helm-charts>
- Cluster API use cases — <https://projectsveltos.io/main/use_cases/clusterAPI/use_case_docker/>
- "Projectsveltos with Hetzner Cloud and Cluster API" — <https://www.reddit.com/r/kubernetes/comments/zemvvo/projectsveltos_with_hetzner_cloud_and_clusterapi/>
