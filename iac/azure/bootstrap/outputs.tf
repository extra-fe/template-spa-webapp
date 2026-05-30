output "tfstate_storage_account" {
  value       = azurerm_storage_account.tfstate.name
  description = "親 iac/azure の backend.hcl に設定する storage_account_name"
}

output "backend_config_hint" {
  description = "親 iac/azure で実行する terraform init -migrate-state 用の backend 設定値"
  value = {
    resource_group_name  = azurerm_resource_group.tfstate.name
    storage_account_name = azurerm_storage_account.tfstate.name
    container_name       = azurerm_storage_container.tfstate.name
    key                  = "azure/terraform.tfstate"
  }
}
