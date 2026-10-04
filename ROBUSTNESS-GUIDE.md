# Robustness Guide — Flatcar + Hetzner + CAPI

> **Status: Vorschläge, NUR TEILWEISE VERIFIZIERT.** Anders als
> `IMPLEMENTATION-PLAN.md` (jede Zeile wurde real ausgeführt) sind die Schritte
> hier ein **Fahrplan** für einen robusten Long-Lived-Cluster. Jede Änderung
> sollte vor Nutzung in einer frischen Umgebung validiert werden — besonders die
> Helm-Werte, MHC-Parameter und der ClusterClass-Umbau.

Ziel: den PoC von „funktioniert einmal" zu „ausfallsicher, wartbar,
reproduzierbar" heben. Reihenfolge = Priorität:

| # | Phase | Warum zuerst |
|---|-------|--------------|
| A | Secrets/Security | teuerster Fehlerfall (Token-Leak) |
| B | Versionen zentralisieren | driftet heute schon (v1.36.4 ×mehrfach) |
| C | Packer deterministisch | Reproduzierbarkeit + Label-Konsistenz |
| D | Manifests härten | explizit, hygienisch, selbstheilend |
| E | OS-Updates entscheiden | größtes Risiko für Long-Lived-Cluster |
| F | Automation/CI | Fehlerquellen reduzieren |
| G | Backup/DR | noch gar nicht existent |

---

## A. Secrets & Security

### A.1 HCLOUD_TOKEN nie in Shell-History / Inline

Heute steht der Token inline in der Doku (`kubectl create secret ... --from-literal=hcloud="$HCLOUD_TOKEN"`) und landet damit in der Shell-History und potenziell in `/proc`-Dumps.

**Sofort umsetzen:**
```bash
# .env (gitignored) statt Inline-Export:
set -a && source .env && set +a

# Secret aus Datei statt --from-literal:
printf '%s' "$HCLOUD_TOKEN" > /tmp/hcloud-token
kubectl create secret generic hcloud -n default \
  --from-file=hcloud=/tmp/hcloud-token \
  --from-file=robot-user=/dev/null \
  --from-file=robot-password=/dev/null
rm /tmp/hcloud-token
```

**Mittelfristig:**
- Token mit GPG/gopass verschlüsseln, erst beim Einsatz entschlüsseln (`export HCLOUD_TOKEN="$(gopass show hetzner/api-token)"`).
- Meilenstein-PoC → Produktion: CAPI-Secrets nicht per Hand, sondern per **External Secrets Operator** (Hetzner-Sekret nicht als externen Anbieter — dafür z. B. SOPS mit Age/Cloud-KMS für das `hcloud` Secret und die Workload-Secrets).

### A.2 SSH-Keys
- Ein projektweiter Key steckt in beiden Templates. Optional: **separater Key pro Node-Pool** (CP vs. Workers), damit ein Leak nicht gleich den ganzen Cluster exponiert.
- Prüfen, ob Root-SSH überhaupt nötig ist (Debug-Zugang). Können Keys später via `users:` aus Templates entfernt und nur für Notfälle injiziert werden?

---

## B. Versionen: eine Quelle, keine Duplikate

Derzeit ist `v1.36.4` **mehrfach** verteilt: `spec.version` (KCP + MD) und je drei Stellen im `ignition.containerLinuxConfig.additionalConfig` (Link-Target, `.raw`-Pfad, `.raw`-URL) sowie die Sysupdate-Conf beider Bootstrap-Configs. CP und Worker duplizieren den kompletten Block. Das driftet garantiert.

### B.1 (Empfohlen) ClusterClass + Topology
Kosten: einmalig Umbau. Nutzen: Node-Templates und Bootstrap-Daten **einmal** definieren, CP und Worker dort ableiten; Version/Image zentral als Parameter.

Umsetzung (zu verifizieren):
```bash
# Guter Start: aus dem KCP/MD-Template ein ClusterClass generieren
clusterctl generate cluster hetzner-cluster \
  --kubernetes-version v1.36.4 \
  --infrastructure hetzner \
  --control-plane-machine-count 1 --worker-machine-count 3 \
  --flavor <dein-flavor>    # Flavor optional
```
Danach: `Cluster` auf `topology:` umstellen, `ClusterClass` anlegen (CP/Worker über `machineDeployments`/`controlPlane.machineTemplate` im Topology referenziert). `HCloudMachineTemplate`/`HCloudMachineClass` lebt dann einmal, nicht zweimal.

### B.2 Bis dahin: Ein-Generator-Skript
Wenn der ClusterClass-Umbau zu früh kommt, als Zwischenlösung ein kleines Skript, das die Manifeste aus **einer** Variablendatei rendert:
```bash
# gen.sh (Platzhalter im Repo, Beispieldatei):
K8S_VERSION=v1.36.4
sed "s|__K8S_VERSION__|$K8S_VERSION|g" templates/control-plane.yaml.in > manifests/control-plane.yaml
```
Wichtig: dann sind die `.yaml`-Dateien Build-Artefakte — im Repo entweder die Quellen **oder** die Artefakte + CI-Validierung (Dateien nicht von Hand editieren).

### B.3 Kubernetes-Binaries: sysext statt Baking
Heute liefert die upstream **sysext-bakery** `kubernetes-v1.36.4-x86-64.raw` die Binaries (kubelet/kubeadm/kubectl + CNI-Plugins). Ignition lädt die `.raw` beim Provisioning; `systemd-sysext` merged sie nach `/usr`. Der Cluster-Aufbau hängt damit an `extensions.flatcar.org`.

**Option 1 (sofort, billig):** Version pinnen (aktuell `v1.36.4`) und die Sysupdate-Conf aus der Bakery nutzen (`systemd-sysupdate.timer`), damit Patchlevel innerhalb derselben Minor-Version automatisch nachgezogen werden. Die Sysupdate-Conf hat upstream `Verify=false` — für Produktion eigene Verifikation/Signaturen einplanen.

**Option 2 (besser, langfristig):** `.raw` in einen internen Mirror/Registry spiegeln (Harbor/OCI) und signieren; Nodes beziehen dann aus dem eigenen Mirror statt direkt von GitHub/flatcar.org.

---

## C. Packer deterministisch

### C.1 Label aus Variable ableiten (Bugfix)
```hcl
snapshot_labels = {
  os              = "flatcar"
  channel         = var.channel
  caph-image-name = "flatcar-${var.channel}-x86"   # statt hardcoded "stable"
}
```
Sonst erzeugt ein `-var channel=beta`-Build ein Snapshot mit falschem `caph-image-name`-Label und CAPH findet „flatcar-stable-x86" nicht.

### C.2 Release pinnen statt `stable` schweben lassen
`flatcar-install -C stable` holt beim Build die **aktuelle** stabile Version. Für reproduzierbare Builds die getestete Version pinnen (z. B. `4593.2.5`), sobald das `flatcar-install`-CLI es hergibt (`--version`-Flag prüfen; ggf. `-V 4593.2.5`). Ergebnis dokumentieren.

**Wichtig:** Pinnen im Snapshot allein genügt nicht — Flatcar aktualisiert sich zur Laufzeit selbst (update-engine). Siehe Phase E.

### C.3 flatcar-install-Skript verifizieren
Das Skript wird per `curl` von GitHub geholt. Mindestens:
- `curl --fail --proto '=https' --tlsv1.2`
- optional GPG-Verifikation (Flatcar signiert Release-Artefakte)

### C.4 Doku synchron halten
Nach dem Commit der Label-Fix in `flatcar.pkr.hcl` müssen `IMPLEMENTATION-PLAN.md` §3.2 / §4.2 angepasst werden: der manuelle `curl`-PUT-Schritt entfällt. Sonst machen Nachfolger den Schritt doppelt bzw. glauben, Label sei manuell zu setzen.

---

## D. Manifeste härten

1. **`selector.matchLabels` explizit setzen** (heute `null`, Template hat `nodepool: worker`):
   ```yaml
   selector:
     matchLabels:
       nodepool: worker
   ```
2. **`replicas: 3`** im MachineDeployment — die Doku (1 CP + 3 Worker) ist Zielkonfiguration; Stand jetzt: 1.
3. **MachineHealthCheck** ergänzen, damit kaputte Nodes remediert statt hängen gelassen werden:
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
   Achtung (verzahnt mit Phase E): MHC/`KubeadmControlPlane` remediert auch bei geplanten Reboots! Reboot-Fenster + großzügige Timeouts wählen (siehe IMPLEMENTATION-PLAN §8).
4. **`.gitignore` erweitern:**
   ```gitignore
   packer_cache/
   crash.*.log
   *.retry
   ```
5. **Leere Platzhalter ehrlich machen:** `scripts/` und `backups/` existieren nicht, werden aber im README gelistet — entweder anlegen oder Zeilen entfernen (oder direkt Phase F/G umsetzen).

---

## E. OS-Updates: Entscheidung treffen (vor Long-Lived!)

Flatcar rebootet sich standardmäßig selbst (update-engine, stable). In einem CAPI-Cluster ist unkontrolliertes Rebooten das größte Stabilitätsrisiko. Die zwei Optionen aus `IMPLEMENTATION-PLAN.md` §8 konkretisiert:

### Option A (empfohlen): kured
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
Begleitmaßnahmen (Pflicht):
- MHC/KCP-Timeouts > max. Reboot-Dauer (siehe D.3, `nodeStartupTimeout: 20m`).
- Nach jedem Cluster-Neubau neu installieren (wie Cilium/CCM).

### Option B: Auto-Update abschalten
Ignition um Systemd-Mask erweitern (in beiden Bootstrap-Configs):
```yaml
    - content: |
        lock=false
      owner: root:root
      path: /etc/flatcar/update.conf        # update-engine pausieren
      permissions: "0644"
    # zusätzlich: locksmithd.service per Ignition maskieren (systemd.units: mask: true)
```
Plus: OS-Rollover ausschließlich über neuen Snapshot + CAPI-Rolling (deterministisch, manuell).

**Entscheidung festhalten** (z. B. in README/Plan §8) — der Status quo (Floating `stable` + Self-Reboot) ist für einen verwalteten Cluster nicht tragfähig.

---

## F. Automation & CI

### F.1 Makefile/Taskfile für die dokumentierten Phasen
Ziel: die manuellen Schritte aus `IMPLEMENTATION-PLAN.md` §3 als idempotente Targets. Beispielgerüst:

```make
.PHONY: image kind init apply cilium ccm verify env
env:
	@test -n "$$HCLOUD_TOKEN" || (echo "HCLOUD_TOKEN fehlt" && exit 1)

image: env
	packer init . && packer build .

kind: env
	EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION=true kind create cluster --name capi-management --wait 5m
	clusterctl init --core cluster-api --bootstrap kubeadm --control-plane kubeadm --infrastructure hetzner

apply: kind
	kubectl apply -f manifests/

cilium:
	helm upgrade --install cilium cilium/cilium --version 1.18.4 -n kube-system \
	  --set ipam.mode=kubernetes --set kubeProxyReplacement=false

ccm:
	# hcloud-credentials Secret + ConfigMap + helm install hccm ...

verify:
	kubectl get nodes -o wide
	clusterctl describe cluster hetzner-cluster
```

### F.2 CI (GitHub Actions o. ä., lightweight)
```yaml
jobs:
  validate:
    steps:
      - run: packer validate flatcar.pkr.hcl
      - run: kubectl apply --dry-run=client -f manifests/   # oder kubeconform
      - run: yamllint manifests/
      - run: gitleaks detect --redact    # Schutz gegen Token/Key-Leaks
```
Pre-commit Hook (optional): `pre-commit install` mit gitleaks + yamllint + kubeconform.

---

## G. Backup & Disaster Recovery (`backups/`-Platzhalter nutzen)

1. **Etcd-Snapshots des Control-Plane** (für 1 CP die einzige Wahrheit):
   - Per CronJob mit `etcdctl snapshot save` (Endpoint `/etc/kubernetes/pki/etcd`-Auth aus Secret) oder **Velero** inkl. Cluster-API-Objekte.
2. **CAPI-Objekt-Backup:** Qualifikanten: Management-Cluster lokal (kind) — Backups dort sind schon „extern", aber der Cluster ist flüchtig. Manifeste sind in Git; fehlen: Secrets (`hcloud`, Bootstrap-Daten). **Kubeconfig + Secrets mit SOPS** sichern.
3. **Wiederherstellungs-Playbook dokumentieren:** Hypothetische Szenarien (CP verloren, Management-Cluster weg, kompletter Verlust) → Schritte + erwartete Zeit. Das fehlt komplett.

---

## Quick-Checkliste (nach Priorität abarbeiten)

- [ ] `.ssh/`-Key separat pro Node-Pool prüfen; Token-Handling aus Shell-History raus (A)
- [ ] `flatcar.pkr.hcl`: Label aus `var.channel`; Release pinnen; Doku §3.2/§4.2 nachziehen (C, B)
- [ ] Bootstrap-Configs: Version pinnen + Sysupdate nutzen (statt Snapshot-Baking); Versionen zentralisieren oder ClusterClass (B)
- [ ] MachineDeployment: `selector.matchLabels` + `replicas: 3`; MachineHealthCheck (D)
- [ ] `.gitignore` erweitern; README-Platzhalter bereinigen (D)
- [ ] OS-Update-Strategie entscheiden + kured (oder Mask) implementiert (E)
- [ ] Makefile + CI-Validation (packer validate, gitleaks) (F)
- [ ] etcd/Velero + Wiederherstellungs-Playbook (G)