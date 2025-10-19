resource "azurerm_service_plan" "plan" {
  name                = "${var.app-name}-${var.environment}-linux-app-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "app" {
  name                            = "${var.app-name}-${var.environment}-linux-app"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  service_plan_id                 = azurerm_service_plan.plan.id
  virtual_network_subnet_id       = azurerm_subnet.app_service.id
  key_vault_reference_identity_id = azurerm_user_assigned_identity.app_uami.id
  site_config {
    container_registry_use_managed_identity       = true
    container_registry_managed_identity_client_id = azurerm_user_assigned_identity.app_uami.client_id
    application_stack {
      docker_registry_url = "https://${azurerm_container_registry.acr.login_server}"
      docker_image_name   = "backend:latest"
    }
    always_on = false
    ip_restriction {
      name        = "AllowFrontDoor"
      priority    = 100
      action      = "Allow"
      service_tag = "AzureFrontDoor.Backend"
    }

    ip_restriction {
      name       = "DenyAllOthers"
      priority   = 200
      action     = "Deny"
      ip_address = "0.0.0.0/0"
    }
  }
  app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    PORT                                = tostring(var.api-expose-port)
    WEBSITES_PORT                       = tostring(var.api-expose-port)
    LOG_LEVEL                           = "Debug"
    CORS_ORIGIN                         = "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
    CORS_METHODS                        = "GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS"
    AUTH0_DOMAIN                        = var.auth0_domain
    AUTH0_AUDIENCE                      = "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
    AUTH_ENABLED                        = "false"
    DATABASE_URL                        = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.postgre_flexible_server_connection_string.id})"
    PRISMA_LOG_LEVEL                    = "query,info,warn,error"
  }
  identity {
    type         = "UserAssigned" # 必要なら "SystemAssigned, UserAssigned" でも可
    identity_ids = [azurerm_user_assigned_identity.app_uami.id]
  }

  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name
    ]
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"

  principal_id   = azurerm_user_assigned_identity.app_uami.principal_id
  principal_type = "ServicePrincipal"

  depends_on = [azurerm_linux_web_app.app]
}

resource "azurerm_log_analytics_workspace" "app_logs" {
  name                = "${var.app-name}-${var.environment}-logws"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "app_logs" {
  name                       = "${var.app-name}-${var.environment}-diagnostic"
  target_resource_id         = azurerm_linux_web_app.app.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.app_logs.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }

  depends_on = [azurerm_linux_web_app.app]
}


resource "azurerm_user_assigned_identity" "app_uami" {
  name                = "${var.app-name}-${var.environment}-uami"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}
