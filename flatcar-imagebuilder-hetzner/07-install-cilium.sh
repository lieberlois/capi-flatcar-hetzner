export KUBECONFIG=hetzner-cluster.kubeconfig

helm repo add cilium https://helm.cilium.io
helm install cilium cilium/cilium --version 1.18.4 \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=false
