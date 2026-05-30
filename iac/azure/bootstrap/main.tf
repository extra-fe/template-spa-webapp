# Terraform state 専用のリソースグループ / Storage Account / コンテナ
#
# 既存のログ用ストレージ等とは分離し、state 専用に作成する (Issue #138)。
# azurerm backend は Blob のリース機構によるロックを内蔵するため別途ロック資源は不要。

resource "azurerm_resource_group" "tfstate" {
  name     = "${var.app-name}-${var.environment}-tfstate-rg"
  location = var.location
}

# state 用 Storage Account
# 名前は 3-24 文字・英数小文字のみ。${app}${env}${random}tfstate でグローバル一意化。
resource "azurerm_storage_account" "tfstate" {
  name                            = "${var.app-name}${var.environment}${random_string.random.result}tfstate"
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  access_tier                     = "Hot"
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  # ネットワーク制限はあえて設定しない (default_action = Allow)。
  # 理由: GitHub-hosted runner は IP が動的なため、ログ用ストレージのような
  # default Deny + ip_rules 方式では CI から state Blob へ到達できない。
  # 代わりに HTTPS 強制 / TLS1.2 / 公開 Blob 禁止で保護し、認証は AAD/RBAC に委ねる。
  # (self-hosted runner や Private Endpoint を使う場合は別途ネットワーク制限を検討)

  blob_properties {
    # state 破損時のロールバック手段として Blob のバージョニングを有効化
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }
}

# state を格納する Blob コンテナ
resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}
