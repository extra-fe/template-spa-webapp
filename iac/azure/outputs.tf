# GitHub Actions の Variables / Secrets に設定すべき値を出力する。
# Key Vault network_acls 有効化に伴い、 ワークフローは Key Vault を直接参照せず
# GH Actions の Variables / Secrets から値を取る方式に変更したため、 初期セットアップ用。
#
# 使い方:
#   terraform output -raw github_actions_variables_json    # Variables (非機密) - 値が出る
#   terraform output -json github_actions_secrets          # Secrets (機密) - -json 指定で値が出る
#
# GitHub UI から設定: Settings → Secrets and variables → Actions → New variable / New secret

# 非機密値 (リソース名等) - GitHub Actions Variables (vars.XXX) として設定
output "github_actions_variables" {
  description = "GitHub Actions Repository Variables に設定する値 (非機密)"
  value = {
    AZURE_RESOURCE_GROUP                = azurerm_resource_group.rg.name
    AZURE_ACR_NAME                      = azurerm_container_registry.acr.name
    AZURE_BACKEND_IMAGE_NAME            = "${var.app-name}-${var.environment}-backend"
    AZURE_BACKEND_WORKING_DIRECTORY     = "/${var.backend-src-root}"
    AZURE_BACKEND_CONTAINER_APP_NAME    = azurerm_container_app.app.name
    AZURE_FRONTEND_WORKING_DIRECTORY    = "/${var.frontend-src-root}"
    AZURE_FRONTEND_STORAGE_ACCOUNT_NAME = azurerm_storage_account.web.name
    AZURE_FRONTDOOR_PROFILE_NAME        = azurerm_cdn_frontdoor_profile.cdn.name
    AZURE_FRONTDOOR_ENDPOINT_NAME       = azurerm_cdn_frontdoor_endpoint.cdn.name
    VITE_API_BASE_URL                   = "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
  }
}

# gh CLI 等で一括設定したい場合に便利な JSON 表現
output "github_actions_variables_json" {
  description = "github_actions_variables の JSON 表現 (gh CLI スクリプト等で使用)"
  value = jsonencode({
    AZURE_RESOURCE_GROUP                = azurerm_resource_group.rg.name
    AZURE_ACR_NAME                      = azurerm_container_registry.acr.name
    AZURE_BACKEND_IMAGE_NAME            = "${var.app-name}-${var.environment}-backend"
    AZURE_BACKEND_WORKING_DIRECTORY     = "/${var.backend-src-root}"
    AZURE_BACKEND_CONTAINER_APP_NAME    = azurerm_container_app.app.name
    AZURE_FRONTEND_WORKING_DIRECTORY    = "/${var.frontend-src-root}"
    AZURE_FRONTEND_STORAGE_ACCOUNT_NAME = azurerm_storage_account.web.name
    AZURE_FRONTDOOR_PROFILE_NAME        = azurerm_cdn_frontdoor_profile.cdn.name
    AZURE_FRONTDOOR_ENDPOINT_NAME       = azurerm_cdn_frontdoor_endpoint.cdn.name
    VITE_API_BASE_URL                   = "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
  })
}

# 機密値 - GitHub Actions Repository Secrets (secrets.XXX) として設定
# AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_SUBSCRIPTION_ID は OIDC 認証用で別途設定済みのため
# ここには含めない (key-vault.tf に github-* secrets として記録されている)
output "github_actions_secrets" {
  description = "GitHub Actions Repository Secrets に設定する値 (機密)"
  sensitive   = true
  value = {
    VITE_AUTH0_CLIENT_ID = auth0_client.app.client_id
    VITE_AUTH0_DOMAIN    = var.auth0_domain
    VITE_AUTH0_AUDIENCE  = "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
  }
}
