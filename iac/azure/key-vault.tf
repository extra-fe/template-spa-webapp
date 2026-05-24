resource "azurerm_key_vault" "vault" {
  name                = "${var.app-name}-${var.environment}-${random_string.random.result}-${var.target-branch}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # ネットワーク制限:
  # - 既定 Deny。 AAD 認証だけでなくネットワーク経路でも防御
  # - bypass = AzureServices で Microsoft の信頼済みサービスを許可
  #   → Container Apps が UAMI で secret を取得する経路は Azure backbone 経由のためここで通る
  # - ip_rules で開発者 PC (local-pc-ip-addresses) と任意の追加 CIDR を許可
  #
  # ⚠ GitHub Actions ワークフロー (deploy-backend-azure.yaml / deploy-frontend-azure.yaml) は
  #    `az keyvault secret show` で Key Vault を読み出すため、 GH-hosted runner の動的 IP からの
  #    アクセスが Deny される。 対処は以下のいずれか:
  #    (a) key-vault-additional-ip-rules に GitHub Actions の IP 範囲を追加 (api.github.com/meta)
  #    (b) self-hosted runner を VNet 内に置く
  #    (c) ワークフロー側で Key Vault 参照する代わりに GitHub Secrets に直接値を入れる
  # ⚠ Key Vault の ip_rules も /31 /32 を受け付けず、 単一 IP は マスク無し で渡す必要がある
  #   (Storage Account と同じ制約。 NSG とはここが違う)
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules = [
      for ip in concat(var.local-pc-ip-addresses, var.key-vault-additional-ip-rules) :
      trimsuffix(ip, "/32")
    ]
  }
}

resource "azurerm_key_vault_secret" "auth0_domain" {
  name         = "AUTH0-DOMAIN"
  value        = var.auth0_domain
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_secret" "auth0_client_id" {
  name         = "AUTH0-CLIENT-ID"
  value        = auth0_client.app.client_id
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_secret" "frontend_working_directory" {
  name         = "FRONTEND-WORKING-DIRECTORY"
  value        = "/${var.frontend-src-root}"
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_secret" "frontend_deploy_storage_account_name" {
  name         = "FRONTEND-STORAGE-ACCOUNT-NAME"
  value        = azurerm_storage_account.web.name
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_secret" "frontend_deploy_resource_group_name" {
  name         = "RESOURCE-GROUP-NAME"
  value        = azurerm_resource_group.rg.name
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_secret" "frontend_deploy_frontdoor_profile_name" {
  name         = "FRONTDOOR-PROFILE-NAME"
  value        = azurerm_cdn_frontdoor_profile.cdn.name
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_secret" "frontend_deploy_frontdoor_endpoint_name" {
  name         = "FRONTDOOR-ENDPOINRT-NAME"
  value        = azurerm_cdn_frontdoor_endpoint.cdn.name
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}



resource "azurerm_key_vault_secret" "github_azure_client_id" {
  name         = "github-AZURE-CLIENT-ID"
  value        = azuread_application_registration.github_actions.client_id
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_secret" "github_azure_subscription_id" {
  name         = "github-AZURE-SUBSCRIPTION-ID"
  value        = data.azurerm_client_config.current.subscription_id
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_secret" "github_azure_tenant_id" {
  name         = "github-AZURE-TENANT-ID"
  value        = data.azurerm_client_config.current.tenant_id
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_access_policy" "terraform_user" {
  key_vault_id = azurerm_key_vault.vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get",
    "List",
    "Delete",
    "Purge",
  ]

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge",
  ]

  certificate_permissions = [
    "Get",
    "List",
    "Delete",
    "Purge",
  ]
  depends_on = [
    azurerm_key_vault.vault
  ]
}

resource "azurerm_key_vault_access_policy" "github_actions" {
  key_vault_id = azurerm_key_vault.vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azuread_service_principal.github_actions.object_id

  key_permissions = [
    "Get",
    "List",
  ]

  secret_permissions = [
    "Get",
    "List",
  ]
  depends_on = [
    azurerm_key_vault.vault,
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_secret" "auth0_audience" {
  name         = "AUTH0-AUDIENCE"
  value        = "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_secret" "api_base_url" {
  name         = "API-BASE-URL"
  value        = "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}


resource "azurerm_key_vault_secret" "acr_name" {
  name         = "ACR-NAME"
  value        = azurerm_container_registry.acr.name
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_secret" "image_name" {
  name         = "IMAGE-NAME"
  value        = "${var.app-name}-${var.environment}-backend"
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_secret" "backend_working_directory" {
  name         = "BACKEND-WORKING-DIRECTORY"
  value        = "/${var.backend-src-root}"
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}


resource "azurerm_key_vault_secret" "backend_container_app_name" {
  name         = "BACKEND-CONTAINER-APP-NAME"
  value        = azurerm_container_app.app.name
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

resource "azurerm_key_vault_secret" "postgre_flexible_server_connection_string" {
  name         = "DATABASE-URL"
  value        = local.database_url
  key_vault_id = azurerm_key_vault.vault.id
  depends_on = [
    azurerm_key_vault_access_policy.terraform_user
  ]
}

# Container App の UAMI に Key Vault Secret 読み取り権限を付与
# UAMI を Container App より先に作成しておくことで、Container App 作成時には
# 既に secret 参照に必要な権限が揃っている (循環依存回避)
resource "azurerm_key_vault_access_policy" "container_app_identity" {
  key_vault_id = azurerm_key_vault.vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.container_app.principal_id

  secret_permissions = ["Get"]
}
