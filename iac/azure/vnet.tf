resource "azurerm_virtual_network" "vnet" {
  name                = "${var.app-name}-${var.environment}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space = [
    "10.0.0.0/24"
  ]
}

# Container Apps 環境用サブネット (旧)
# 注: container_apps (10.0.0.0/27) はかつて Container Apps 環境を載せていたが、
# 環境の削除に長時間かかる (ScheduledForDelete) 状態のしがらみで、 同じサブネットで
# 環境を作り直すと不安定になる事象を確認したため、 _v2 サブネットに移行 (下記)。
# こちらのサブネットは Azure 側の旧環境クリーンアップ完了後に手動削除予定。
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

# Container Apps 環境用サブネット (v2 — 現役)
# - Workload Profiles 環境は /27 (32 IPs) 以上が必須
# - Microsoft.App/environments に delegation
resource "azurerm_subnet" "container_apps_v2" {
  name                 = "${var.app-name}-${var.environment}-containerapps-v2"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    "10.0.0.64/27"
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
