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

variable "vm_size" {
  type        = string
  description = "VM size [Standard_DS1_v2,Standard_DS2_v3,Standard_D2ads_v5]"
  default     = "Standard_D2ads_v5"
}
variable "os_publisher" {
  type        = string
  description = "Operating System Publisher [RedHat,SUSE]"
  default     = "RedHat"
}
variable "os_offer" {
  type        = string
  description = "Operating System Offer [RHEL,sles]"
  default     = "RHEL"
}
variable "os_sku" {
  type        = string
  description = "Operating System SKU [93-gen2,15-sp3]"
  default     = "93-gen2"
}
variable "os_version" {
  type        = string
  description = "Operating System Version [latest,9.3.2024022812]"
  default     = "latest"
}

variable "remote_exec_cmds" {
  type        = list(string)
  description = "list of command to run when ready via SSH connexion"
  default     = [
    "cat /etc/*release*"
  ]
}

variable "local_rpm_folder_path" {
  type    = string
  description = "Path to the local folder where rpm are stored, like: '../../../apim/4.x/'"
  default = ""
}
