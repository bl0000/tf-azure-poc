resource "random_pet" "prefix" {
  prefix = var.resource_group_name_prefix
  length = 1
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name = "${random_pet.prefix.id}-rg"
}

# Virtual Network
resource "azurerm_virtual_network" "my_terraform_network" {
  name = "${random_pet.prefix.id}-vnet"
  address_space = ["10.40.0.0/16"]
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnet 1
resource "azurerm_subnet" "my_terraform_subnet_1" {
  name = "subnet-1"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.my_terraform_network.name
  address_prefixes = ["10.40.10.0/24"]
}

# Subnet 2
resource "azurerm_subnet" "my_terraform_subnet_2" {
  name = "subnet-2"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.my_terraform_network.name
  address_prefixes = ["10.40.15.0/24"]
}

# Create SQL server name
resource "random_pet" "azurerm_mssql_server_name" {
  prefix = "sql"
}

# Random password for SQL server
resource "random_password" "admin_password" {
  count       = var.admin_password == null ? 1 : 0
  length      = 20
  special     = true
  min_numeric = 1
  min_upper   = 1
  min_lower   = 1
  min_special = 1
}

locals {
  admin_password = try(random_password.admin_password[0].result, var.admin_password)
}

# Create SQL server
resource "azurerm_mssql_server" "server" {
  name                         = random_pet.azurerm_mssql_server_name.id
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  administrator_login          = var.admin_username
  administrator_login_password = local.admin_password
  version                      = "12.0"
}

# Create SQL database
resource "azurerm_mssql_database" "db" {
  name      = var.sql_db_name
  server_id = azurerm_mssql_server.server.id
}

# Create private endpoint for SQL server
resource "azurerm_private_endpoint" "my_terraform_endpoint" {
  name                = "private-endpoint-sql"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.my_terraform_subnet_1.id

  private_service_connection {
    name                           = "private-serviceconnection"
    private_connection_resource_id = azurerm_mssql_server.server.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.my_terraform_dns_zone.id]
  }
}

# Create private DNS zone
resource "azurerm_private_dns_zone" "my_terraform_dns_zone" {
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

# Create virtual network link
resource "azurerm_private_dns_zone_virtual_network_link" "my_terraform_vnet_link" {
  name                  = "vnet-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.my_terraform_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.my_terraform_network.id
}

# New vnet to existing vnet
resource "azurerm_virtual_network_peering" "peer_new_to_existing" {
  name                      = "peer-new-to-existing"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.my_terraform_network.name
  remote_virtual_network_id = var.existing_vnet_id
}

# Existing vnet to new vnet
resource "azurerm_virtual_network_peering" "peer_existing_to_new" {
  name                      = "peer-existing-to-new"
  resource_group_name       = var.existing_vnet_rg
  virtual_network_name      = var.existing_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.my_terraform_network.id
}