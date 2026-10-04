# 1. Feature Gate für Ignition zwingend VOR clusterctl/kind aktivieren
export EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION=true

# 2. Lokalen kind Cluster als Management-Ebene starten
kind create cluster --name capi-management --wait 5m

# 3. Hetzner API Token setzen
export HCLOUD_TOKEN="***REMOVED-TOKEN***"

# 4. CAPI und Hetzner Provider (CAPH) initialisieren
clusterctl init --core cluster-api \
  --bootstrap kubeadm \
  --control-plane kubeadm \
  --infrastructure hetzner

# 5. Warten, bis alle Controller-Pods bereit sind
kubectl get pods -A -w
