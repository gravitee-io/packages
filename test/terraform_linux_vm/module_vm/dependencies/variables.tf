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
