terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.14"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = true
  pm_debug            = true
}

resource "proxmox_vm_qemu" "opendiscourse" {
  name        = "opendiscourse"
  target_node = var.target_node
  clone       = var.template_name
  full_clone  = true
  agent       = 1
  os_type     = "cloud-init"
  cores       = 4
  sockets     = 1
  cpu         = "host"
  memory      = 16384
  scsihw      = "virtio-scsi-pci"
  bootdisk    = "scsi0"
  
  disk {
    slot     = 0
    size     = "100G"
    type     = "scsi"
    storage  = var.storage_pool
    iothread = 1
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  ipconfig0 = "ip=${var.vm_ip}/24,gw=${var.vm_gateway}"
  ciuser    = var.vm_username
  cipassword = var.vm_password
  sshkeys   = <<-EOT
    ${file("~/.ssh/id_rsa.pub")}
  EOT

  # Cloud-init settings
  nameserver = "8.8.8.8"
  searchdomain = var.domain
  
  # Initialization script
  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get install -y git curl jq",
      "git clone https://github.com/yourusername/opendiscourse.git /opt/opendiscourse"
    ]
    
    connection {
      type        = "ssh"
      user        = var.vm_username
      private_key = file("~/.ssh/id_rsa")
      host        = var.vm_ip
    }
  }
}
