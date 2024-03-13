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

variable "vm_size" {
  type        = string
  description = "VM size [Standard_DS1_v2,Standard_DS2_v3,Standard_D2ads_v5]"
  default     = "Standard_D2ads_v5"
}
variable "os_publisher" {
  type        = string
  description = "Operating System Publisher [RedHat,SUSE]"
  default     = "procomputers"
}
variable "os_name" {
  type        = string
  description = "Operating System Offer [centos-stream-9-minimal,centos-7-minimal]"
  default     = "centos-stream-9-minimal"
}
variable "os_version" {
  type        = string
  description = "Operating System Version [latest,8.0.7]"
  default     = "latest"
}

