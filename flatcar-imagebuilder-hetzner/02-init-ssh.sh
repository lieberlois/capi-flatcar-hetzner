ssh-keygen -t ed25519 -N "" -f ./hetzner-flatcar-key
hcloud ssh-key create --name hetzner-flatcar-key --public-key-from-file ./hetzner-flatcar-key.pub
