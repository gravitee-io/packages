resource "random_pet" "ssh_key_name" {
  prefix    = "ssh"
  separator = ""
}

resource "azapi_resource_action" "ssh_public_key_gen" {
  depends_on = [azapi_resource.ssh_public_key]
  type        = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  resource_id = azapi_resource.ssh_public_key.id
  action      = "generateKeyPair"
  method      = "POST"

  response_export_values = ["publicKey", "privateKey"]
}

resource "azapi_resource" "ssh_public_key" {
  depends_on = [random_pet.ssh_key_name, data.azurerm_resource_group.rg]
  type      = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  name      = random_pet.ssh_key_name.id
  location  = data.azurerm_resource_group.rg.location
  parent_id = data.azurerm_resource_group.rg.id
}

resource "local_sensitive_file" "ssh_private_key" {
  depends_on = [random_pet.tf_resource_prefix, azapi_resource_action.ssh_public_key_gen]
  content  = jsondecode(azapi_resource_action.ssh_public_key_gen.output).privateKey
  filename = var.ssh_key_filename != "" ? var.ssh_key_filename : "${random_pet.tf_resource_prefix.id}_id_rsa.pem"
  file_permission = "0600"
}
