# Terraform configuration for provisioning a single VM on Hetzner Cloud to host OpenDiscourse + Nextcloud + WireGuard + LAMP
# NOTE: Adjust server_type to a Hetzner flavor that matches your desired vCPU/RAM/disk (e.g., cx41, cpx41, etc.)
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.39"
    }
  }
  required_version = ">= 1.2.0"
}

provider "hcloud" {
  token = var.hcloud_token
}

# Create an SSH key on Hetzner (if key doesn't exist, this will create)
resource "hcloud_ssh_key" "user_key" {
  name       = var.ssh_key_name
  public_key = file(var.ssh_public_key_path)
}

# Optional volume to attach for application data (persistant storage)
resource "hcloud_volume" "data" {
  name      = "${var.server_name}-data"
  size      = var.data_volume_gb
  location  = var.location
  format    = "ext4"
}

# Create the server
resource "hcloud_server" "opendiscourse" {
  name        = var.server_name
  server_type = var.server_type
  image       = var.image
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.user_key.id]

  # cloud-init user-data will install docker and run the installer
  user_data = file("${path.module}/cloud-init/user-data.yaml")

  # attach volume after server is created
  depends_on = [hcloud_volume.data]
  lifecycle {
    create_before_destroy = true
  }
}

# Attach the volume to the server
resource "hcloud_volume_attachment" "data_attach" {
  server_id = hcloud_server.opendiscourse.id
  volume_id = hcloud_volume.data.id
  automount = true
}

# Floating IP (optional) - create and assign
resource "hcloud_floating_ip" "fip" {
  type     = "ipv4"
  location = var.location
}

resource "hcloud_floating_ip_assignment" "assign" {
  floating_ip_id = hcloud_floating_ip.fip.id
  server_id      = hcloud_server.opendiscourse.id
}

# Security note: Hetzner's firewall or cloud-init will configure UFW in user-data.
# Outputs
output "server_ip" {
  value = hcloud_floating_ip.fip.ip
}

output "server_name" {
  value = hcloud_server.opendiscourse.name
}