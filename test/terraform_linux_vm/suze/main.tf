variable "allowed_ips" {
  type        = string
  description = "Used to filter IP which have access to the Virtual Machine, could be a prefix, CIDR or a match like `*`"
  default     = "*"
}

variable "ssh_key_filename" {
  type        = string
  description = "Overwrite default random ssh key filename"
  default     = ""
}

variable "username" {
  type        = string
  description = "The username for the local account that will be created on the new VM."
  default     = "azureadmin"
}

variable "remote_exec_cmds" {
  type        = list(string)
  description = "list of command to run when ready via SSH connexion"
  default     = [
    "sleep 45", // wait a bit to let the system start, if not, SUSEConnect will failed
    "sudo SUSEConnect --product PackageHub/15.6/x86_64 --auto-agree-with-licenses",
    "sudo zypper --non-interactive in tmux",
    "chmod u+x *.sh",
    "tmux new-session \\; send-keys './install_suze.sh' C-m \\; detach-client"
  ]
}

variable "local_rpm_folder_path" {
  type    = string
  description = "Path to the local folder where rpm are stored, like: '../../../apim/4.x/'"
  default = ""
}

module "suze-vm" {
  source = "../module_vm"
  username = var.username
  allowed_ips = var.allowed_ips
  ssh_key_filename = var.ssh_key_filename
  local_rpm_folder_path = var.local_rpm_folder_path

  vm_size = "Standard_D2ads_v5"
  os_publisher = "suse"
  os_offer = "sles-15-sp6-basic"
  os_sku = "gen2"
  os_version = "latest" // 2024.02.07
  remote_exec_cmds = var.remote_exec_cmds
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
