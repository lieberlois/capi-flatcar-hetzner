export KUBECONFIG=hetzner-cluster.kubeconfig

helm repo add hcloud https://charts.hetzner.cloud

kubectl -n kube-system create secret generic hcloud-credentials \
  --from-literal=hcloud-token="$HCLOUD_TOKEN" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: hcloud-ccm-config
  namespace: kube-system
data:
  cloud-config: |
    token-location: /etc/hcloud/token
    network: hetzner-cluster
    private-network-only: false
EOF

helm upgrade --install hccm hcloud/hcloud-cloud-controller-manager \
  --namespace kube-system \
  --set secretName=hcloud-credentials \
  --set secretKeyName=hcloud-token \
  --set cloudConfigName=hcloud-ccm-config