# Terraform outputs for the Hetzner single-VM deployment

output "server_ip" {
  description = "Assigned floating IP for the server (if enable_floating_ip=true)"
  value       = hcloud_floating_ip.fip.ip
}

output "server_name" {
  description = "Name of the created Hetzner server"
  value       = hcloud_server.opendiscourse.name
}

output "server_id" {
  description = "Hetzner server ID"
  value       = hcloud_server.opendiscourse.id
}

output "data_volume_id" {
  description = "ID of the attached data volume"
  value       = hcloud_volume.data.id
}

output "ssh_fingerprint" {
  description = "SSH key fingerprint uploaded to Hetzner"
  value       = hcloud_ssh_key.user_key.fingerprint
}