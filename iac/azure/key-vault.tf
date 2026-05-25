resource "azurerm_key_vault" "vault" {
  name                = "${var.app-name}-${var.environment}-${random_string.random.result}-${var.target-branch}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # ネットワーク制限:
  # - 既定 Deny。 AAD 認証だけでなくネットワーク経路でも防御
  # - bypass = AzureServices で Microsoft の信頼済みサービスを許可
  # - ip_rules で開発者 PC (local-pc-ip-addresses) と任意の追加 CIDR を許可
  #
  # ⚠ Key Vault の ip_rules は /31 /32 を受け付けず、 単一 IP は マスク無し で渡す必要がある
  #   (Storage Account と同じ制約。 NSG とはここが違う)
  #
  # 補足: ランタイムでこの KV を直接参照するリソースは現在無い:
  # - Container App の DATABASE-URL は CA secret store に直接埋め込む構成 (container-apps.tf 参照)
  # - GitHub Actions ワークフローは GitHub Environments の Variables/Secrets を直接参照
  # この KV は OIDC 用 SP 情報 (github-AZURE-*) の保存先としてのみ機能している。
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules = [
      for ip in concat(var.local-pc-ip-addresses, var.key-vault-additional-ip-rules) :
      trimsuffix(ip, "/32")
    ]
  }
}

# OIDC 用 SP 情報の保存。 docs/azure-github-actions-setup.md の手順で
# 開発者がこの KV から値を取り出して GitHub repository secrets に登録する想定。
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

# Terraform 自身が secret を作成・削除できるよう、 実行ユーザーに権限を付与
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
