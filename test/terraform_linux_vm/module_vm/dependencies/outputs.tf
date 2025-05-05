output "random_pet-tf_resource_prefix-id" {
  value = random_pet.tf_resource_prefix.id
}

output "azurerm_resource_group-rg-location" {
  value = data.azurerm_resource_group.rg.location
}

output "azurerm_resource_group-rg-name" {
  value = data.azurerm_resource_group.rg.name
}

output "azurerm_network_interface-rpm_tf_nic-id" {
  value = azurerm_network_interface.rpm_tf_nic.id
}

output "azapi_resource_action-ssh_public_key_gen-output" {
  value = azapi_resource_action.ssh_public_key_gen.output
}

output "azurerm_storage_account-rpm_storage_account-primary_blob_endpoint" {
  value = azurerm_storage_account.rpm_storage_account.primary_blob_endpoint
}

output "local_sensitive_file-ssh_private_key-filename" {
  value = local_sensitive_file.ssh_private_key.filename
}
