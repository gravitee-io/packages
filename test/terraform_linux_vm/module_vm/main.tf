module "dependencies" {
  source = "./dependencies"
  allowed_ips = var.allowed_ips
  ssh_key_filename = var.ssh_key_filename
}

# Agreement of OS offer
#resource "azurerm_marketplace_agreement" "this" {
#  publisher = "redhat"
#  offer     = "rh-rhel"
#  plan      = "rh-rhel9"
#}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "rpm_vm" {
  depends_on = [module.dependencies]
  name                  = "${module.dependencies.random_pet-tf_resource_prefix-id}_VM"
  location              = module.dependencies.azurerm_resource_group-rg-location
  resource_group_name   = module.dependencies.azurerm_resource_group-rg-name
  network_interface_ids = [module.dependencies.azurerm_network_interface-rpm_tf_nic-id]
  size                  = var.vm_size

  os_disk {
    name                 = "${module.dependencies.random_pet-tf_resource_prefix-id}_OsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  #  plan {
  #    name      = "rh-rhel9"
  #    product   = "rh-rhel"
  #    publisher = "RedHat"
  #  }

  source_image_reference {
    publisher = var.os_publisher
    offer     = var.os_offer
    sku       = var.os_sku
    version   = var.os_version
  }

  computer_name  = replace(module.dependencies.random_pet-tf_resource_prefix-id, "_", "")
  admin_username = var.username

  admin_ssh_key {
    username   = var.username
    public_key = jsondecode(module.dependencies.azapi_resource_action-ssh_public_key_gen-output).publicKey
  }

  boot_diagnostics {
    storage_account_uri = module.dependencies.azurerm_storage_account-rpm_storage_account-primary_blob_endpoint
  }

  connection {
    type = "ssh"
    user = var.username
    private_key = jsondecode(module.dependencies.azapi_resource_action-ssh_public_key_gen-output).privateKey
    host = self.public_ip_address
  }

  provisioner "file" {
    source = "${path.module}/install_redhat.sh"
    destination = "install_redhat.sh"
  }

  provisioner "file" {
    source = "${path.module}/install_suze.sh"
    destination = "install_suze.sh"
  }

  # Hack mode on:
  # It is not possible in terraform to have conditional on provisioner
  # So if the local_rpm_folder_path variable is not set, we re-upload the install_redhat.sh script ...
  provisioner "file" {
    source = var.local_rpm_folder_path != null && var.local_rpm_folder_path != "" ? var.local_rpm_folder_path : "${path.module}/install_redhat.sh"
    destination = var.local_rpm_folder_path != null && var.local_rpm_folder_path != "" ? "rpms" : "install_redhat.sh"
  }

  provisioner "remote-exec" {
    inline = var.remote_exec_cmds
  }
}
