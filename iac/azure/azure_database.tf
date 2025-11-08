resource "random_string" "db_password" {
  length  = 12
  upper   = true
  lower   = true
  numeric = true
  special = false
}

locals {
  password   = random_string.db_password.result
  encoded_pw = urlencode(local.password)
  database_url = join("",
    [
      "postgresql://",
      "${azurerm_postgresql_flexible_server.db_server.administrator_login}",
      ":",
      "${local.encoded_pw}",
      "@",
      "${azurerm_postgresql_flexible_server.db_server.fqdn}",
      ":",
      "5432",
      "/",
      "${azurerm_postgresql_flexible_server_database.db.name}",
      "?",
      "sslmode=require"
    ]
  )
}

resource "azurerm_private_dns_zone" "postgres_dns" {
  name                = "private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_postgresql_flexible_server" "db_server" {
  administrator_login               = "${var.app-name}${var.environment}admin"
  administrator_password_wo         = local.password
  administrator_password_wo_version = 0
  backup_retention_days             = 7
  delegated_subnet_id               = azurerm_subnet.db.id
  location                          = azurerm_resource_group.rg.location
  name                              = "${var.app-name}-${var.environment}-db-server"
  private_dns_zone_id               = azurerm_private_dns_zone.postgres_dns.id
  public_network_access_enabled     = false
  resource_group_name               = azurerm_resource_group.rg.name
  sku_name                          = "B_Standard_B1ms"
  storage_mb                        = 32768
  storage_tier                      = "P4"
  tags                              = {}
  zone                              = "2"
  version                           = "16"
  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }
}

resource "azurerm_postgresql_flexible_server_database" "db" {
  name      = "${var.app-name}-${var.environment}-db"
  server_id = azurerm_postgresql_flexible_server.db_server.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}


resource "azurerm_private_dns_zone_virtual_network_link" "link" {
  name                  = "${var.app-name}-${var.environment}-dns-vnet-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres_dns.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}
