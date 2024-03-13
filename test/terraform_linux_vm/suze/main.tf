variable "allowed_ips" {
  type        = string
  description = "Used to filter IP which have access to the Virtual Machine, could be a prefix, CIDR or a match like `*`"
  default     = "*"
}

variable "username" {
  type        = string
  description = "The username for the local account that will be created on the new VM."
  default     = "azureadmin"
}

module "suze-vm" {
  source = "../module_vm"
  username = var.username
  allowed_ips = var.allowed_ips

  vm_size = "Standard_D2ads_v5"
  os_publisher = "suse"
  os_offer = "sles-15-sp5-basic"
  os_sku = "gen2"
  os_version = "latest" // 2024.02.07
  remote_exec_cmds = [
    "sleep 45", // wait a bit to let the system start, if not, SUSEConnect will failed
    "sudo SUSEConnect --product PackageHub/15.5/x86_64 --auto-agree-with-licenses",
    "sudo zypper --non-interactive in tmux",
    "chmod u+x *.sh",
    "tmux new-session \\; send-keys './install_suze.sh install_prerequities' C-m \\; detach-client"
  ]
}

output "public_ip_address" {
  value = module.suze-vm.public_ip_address
}

output "ssh_command_to_connect" {
  value = module.suze-vm.ssh_command_to_connect
}

output "scp_command_to_push_rpm" {
  value = module.suze-vm.scp_command_to_push_rpm
}
