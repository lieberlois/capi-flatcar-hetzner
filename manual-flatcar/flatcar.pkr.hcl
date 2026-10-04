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

  # Kubernetes binaries/units are no longer baked into the image.
  # The upstream sysext-bakery kubernetes.raw is fetched at provisioning time
  # via Ignition (see manual-flatcar/manifests/*.yaml) and merged into /usr by
  # Flatcar's systemd-sysext. This snapshot is a plain, labeled Flatcar base.
}