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

variable "os_sku" {
  type        = string
  description = "Operating System SKU [93-gen2,8-gen2,7.6,6.9]"
  default     = "93-gen2"
}

variable "remote_exec_cmds" {
  type        = list(string)
  description = "list of command to run when ready via SSH connexion"
  default     = [
    "sudo yum install -y tmux",
    "chmod u+x install_*.sh",
    "tmux new-session \\; send-keys './install_redhat.sh' C-m \\; detach-client"
  ]
}

variable "local_rpm_folder_path" {
  type    = string
  description = "Path to the local folder where rpm are stored, like: '../../../apim/4.x/'"
  default = ""
}

module "redhat-vm" {
  source = "../module_vm"
  username = var.username
  allowed_ips = var.allowed_ips
  ssh_key_filename = var.ssh_key_filename
  local_rpm_folder_path = var.local_rpm_folder_path

  vm_size = "Standard_D2ads_v5"
  os_publisher = "RedHat"
  os_offer = "RHEL"
  os_sku = var.os_sku
  os_version = "latest"
  remote_exec_cmds = var.remote_exec_cmds
}

output "public_ip_address" {
  value = module.redhat-vm.public_ip_address
}

output "ssh_command_to_connect" {
  value = module.redhat-vm.ssh_command_to_connect
}

output "scp_command_to_push_rpm" {
  value = module.redhat-vm.scp_command_to_push_rpm
}
