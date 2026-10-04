kubectl create secret generic hcloud -n default \
  --from-literal=hcloud="$HCLOUD_TOKEN" \
  --from-literal=robot-user='' \
  --from-literal=robot-password=''
