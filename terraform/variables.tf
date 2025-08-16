# Variables for Hetzner single-VM provisioning for OpenDiscourse + Nextcloud + WireGuard + LAMP

variable "hcloud_token" {
  description = "Hetzner Cloud API token (required)"
  type        = string
  sensitive   = true
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file to upload to Hetzner (no ~ expansion; provide absolute or repo-relative path)"
  type        = string
}

variable "ssh_key_name" {
  description = "Name of the SSH key in Hetzner"
  type        = string
  default     = "opendiscourse-key"
}

variable "server_name" {
  description = "Name for the created server"
  type        = string
  default     = "opendiscourse-vm"
}

variable "server_type" {
  description = "Hetzner server type (choose a flavor that maps to desired vCPU/RAM). Example: cpx41 (8 vCPU, 32 GB)"
  type        = string
  default     = "cpx41"
}

variable "image" {
  description = "Server image to use (Ubuntu recommended)"
  type        = string
  default     = "ubuntu-22.04"
}

variable "location" {
  description = "Hetzner location (e.g., nbg1, fsn1, hel1)"
  type        = string
  default     = "nbg1"
}

variable "data_volume_gb" {
  description = "Size in GB for the attached data volume (used for app uploads, Nextcloud data, DB storage)"
  type        = number
  default     = 500
}

variable "enable_floating_ip" {
  description = "Set to true to allocate and attach a floating IP"
  type        = bool
  default     = true
}