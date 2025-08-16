variable "pm_api_url" {
  description = "Proxmox API URL (e.g., https://proxmox-server:8006/api2/json)"
  type        = string
  sensitive   = true
}

variable "pm_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
  sensitive   = true
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "target_node" {
  description = "Proxmox node name where the VM will be created"
  type        = string
  default     = "pve"
}

variable "template_name" {
  description = "Name of the template to clone"
  type        = string
  default     = "ubuntu-2204-cloudinit"
}

variable "storage_pool" {
  description = "Storage pool for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "vm_ip" {
  description = "IP address for the VM"
  type        = string
}

variable "vm_gateway" {
  description = "Default gateway for the VM"
  type        = string
}

variable "vm_username" {
  description = "Default username for the VM"
  type        = string
  default     = "opendiscourse"
}

variable "vm_password" {
  description = "Password for the default user"
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "Domain name for the OpenDiscourse installation"
  type        = string
  default     = "opendiscourse.net"
}
