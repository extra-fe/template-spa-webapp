resource "azurerm_virtual_network" "vnet" {
  name                = "${var.app-name}-${var.environment}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space = [
    "10.0.0.0/24"
  ]
}

# Container Apps 環境用サブネット
# - Workload Profiles 環境は /27 (32 IPs) 以上が必須
# - Microsoft.App/environments に delegation
resource "azurerm_subnet" "container_apps" {
  name                 = "${var.app-name}-${var.environment}-containerapps"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    "10.0.0.0/27"
  ]
  delegation {
    name = "delegation"
    service_delegation {
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
      name = "Microsoft.App/environments"
    }
  }
}

resource "azurerm_subnet" "db" {
  name                 = "${var.app-name}-${var.environment}-db"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    "10.0.0.32/29"
  ]
  service_endpoints = [
    "Microsoft.Storage",
  ]
  delegation {
    name = "delegation"

    service_delegation {
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
    }
  }
}

resource "azurerm_subnet" "default" {
  name                 = "${var.app-name}-${var.environment}-default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    "10.0.0.48/28"
  ]
}
