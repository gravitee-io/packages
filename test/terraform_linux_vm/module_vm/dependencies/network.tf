# Create virtual network
resource "azurerm_virtual_network" "rpm_network" {
  depends_on = [data.azurerm_resource_group.rg]
  name                = "${random_pet.tf_resource_prefix.id}_Vnet"
  address_space       = ["10.0.0.0/16"]
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
}

# Create subnet
resource "azurerm_subnet" "rpm_subnet" {
  depends_on = [data.azurerm_resource_group.rg, random_pet.tf_resource_prefix]
  name                 = "${random_pet.tf_resource_prefix.id}_Subnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.rpm_network.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "rpm_public_ip" {
  depends_on = [data.azurerm_resource_group.rg, random_pet.tf_resource_prefix]
  name                = "${random_pet.tf_resource_prefix.id}_PublicIP"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "rpm_tf_nsg" {
  depends_on = [data.azurerm_resource_group.rg, random_pet.tf_resource_prefix]
  name                = "${random_pet.tf_resource_prefix.id}_NetworkSecurityGroup"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ips
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "APIM"
    priority                   = 1101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080-8085"
    source_address_prefix      = var.allowed_ips
    destination_address_prefix = "*"
  }
}

# Create network interface
resource "azurerm_network_interface" "rpm_tf_nic" {
  depends_on = [
    data.azurerm_resource_group.rg,
    random_pet.tf_resource_prefix,
    azurerm_subnet.rpm_subnet,
    azurerm_public_ip.rpm_public_ip
  ]
  name                = "${random_pet.tf_resource_prefix.id}_NIC"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "${random_pet.tf_resource_prefix.id}_nic_configuration"
    subnet_id                     = azurerm_subnet.rpm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.rpm_public_ip.id
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "rpm_nic_sg_asso" {
  depends_on = [azurerm_network_interface.rpm_tf_nic, azurerm_network_security_group.rpm_tf_nsg]
  network_interface_id      = azurerm_network_interface.rpm_tf_nic.id
  network_security_group_id = azurerm_network_security_group.rpm_tf_nsg.id
}
