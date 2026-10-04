packer {
  required_plugins {
    hcloud = {
      source  = "github.com/hetznercloud/hcloud"
      version = "~> 1.4.0"
    }
  }
}

variable "channel" {
  type    = string
  default = "stable"
}

variable "hcloud_token" {
  type      = string
  default   = env("HCLOUD_TOKEN")
  sensitive = true
}

source "hcloud" "flatcar" {
  token = var.hcloud_token

  image    = "ubuntu-24.04"
  location = "fsn1"
  rescue   = "linux64"

  snapshot_labels = {
    os              = "flatcar"
    channel         = var.channel
    caph-image-name = "flatcar-stable-x86"
  }

  ssh_username = "root"
}

build {
  source "hcloud.flatcar" {
    name          = "x86"
    server_type   = "cx23"
    snapshot_name = "flatcar-${var.channel}-x86"
  }

  provisioner "shell" {
    inline = [
      "apt-get -y install gawk",
      "curl -fsSLO --retry-delay 1 --retry 60 --retry-connrefused --retry-max-time 60 --connect-timeout 20 https://raw.githubusercontent.com/flatcar/init/flatcar-master/bin/flatcar-install",
      "chmod +x flatcar-install",
      "./flatcar-install -s -o hetzner -C ${var.channel}",
    ]
  }

  # ---- copy the system‑extension into the future root partition ----
  provisioner "file" {
    source      = "capi-logic.tar.xz"
    destination = "/tmp/capi-logic.tar.xz"
  }

  provisioner "shell" {
    inline = [
      "ROOTDEV=$(blkid -l -t LABEL=ROOT -o device)",
      "mkdir -p /mnt/rootfs",
      "mount $ROOTDEV /mnt/rootfs",
      "mkdir -p /mnt/rootfs/usr/lib/extensions",
      "tar -C /mnt/rootfs/usr/lib/extensions -xJf /tmp/capi-logic.tar.xz",
      "umount /mnt/rootfs",
      "rm /tmp/capi-logic.tar.xz",
    ]
  }
}