resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.app-name}-${var.environment}"
  location = var.location
}
