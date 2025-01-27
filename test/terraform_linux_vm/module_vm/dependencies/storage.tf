# Create storage account for boot diagnostics
resource "azurerm_storage_account" "rpm_storage_account" {
  depends_on = [random_id.random_id, data.azurerm_resource_group.rg]
  name                     = "diag${random_id.random_id.hex}"
  location                 = data.azurerm_resource_group.rg.location
  resource_group_name      = data.azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
