resource "azurerm_service_plan" "plan" {
  name                = "${var.app-name}-${var.environment}-linux-app-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "F1" # Free Tier
}


resource "azurerm_linux_web_app" "app" {
  name                = "${var.app-name}-${var.environment}-linux-app"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.plan.id

  site_config {
    application_stack {
      docker_image_name        = "${var.app-name}-${var.environment}-backend:latest"
      docker_registry_url      = "https://${azurerm_container_registry.acr.login_server}"
      docker_registry_username = azurerm_container_registry.acr.admin_username
      docker_registry_password = azurerm_container_registry.acr.admin_password
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
    LOG_LEVEL                           = "Debug"
    CORS_ORIGIN                         = "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
    CORS_METHODS                        = "GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS"
    AUTH0_DOMAIN                        = var.auth0_domain
    AUTH0_AUDIENCE                      = "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
  }
  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name
    ]
  }
}

