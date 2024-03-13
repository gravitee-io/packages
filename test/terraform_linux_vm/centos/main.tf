module "dependencies" {
  source = "../module_vm/dependencies"
  allowed_ips = var.allowed_ips
}


# Agreement of OS offer
resource "azurerm_marketplace_agreement" "this" {
  publisher = "procomputers"
  offer     = var.os_name
  plan      = var.os_name
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "rpm_vm" {
  depends_on = [module.dependencies ,azurerm_marketplace_agreement.this]

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

  plan {
    name      = var.os_name
    product   = var.os_name
    publisher = "procomputers"
  }

  source_image_reference {
    publisher = var.os_publisher
    offer     = var.os_name
    sku       = var.os_name
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
    source = "../module_vm/install_redhat.sh"
    destination = "install_redhat.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install -y tmux",
      "chmod u+x install_*.sh",
      "tmux new-session \\; send-keys './install_redhat.sh' C-m \\; detach-client"
    ]
  }
}

output "public_ip_address" {
  value = azurerm_linux_virtual_machine.rpm_vm.public_ip_address
}

output "ssh_command_to_connect" {
  value = "ssh -i ${module.dependencies.local_sensitive_file-ssh_private_key-filename} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no matthieu@${azurerm_linux_virtual_machine.rpm_vm.public_ip_address}"
}

output "scp_command_to_push_rpm" {
  value = "scp -i ${module.dependencies.local_sensitive_file-ssh_private_key-filename} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ../../../apim/4.x/graviteeio-apim-*-4x*.rpm matthieu@${azurerm_linux_virtual_machine.rpm_vm.public_ip_address}:."
}
