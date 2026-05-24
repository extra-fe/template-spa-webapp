# ログ用ストレージアカウント
# VNet Flow Logs / Front Door ログを格納するためのアーカイブ用ストレージ
# 分析クエリは Log Analytics Workspace (KQL) 側で実施する想定で、ここはあくまで長期保管用
resource "azurerm_storage_account" "logs" {
  name                            = "${var.app-name}${var.environment}${random_string.random.result}logs"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  access_tier                     = "Hot"
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true
  shared_access_key_enabled       = true # Flow Logs / diagnostic 配信に必要
  tags                            = {}

  blob_properties {
    versioning_enabled = false

    container_delete_retention_policy {
      days = 7
    }

    delete_retention_policy {
      days                     = 7
      permanent_delete_enabled = false
    }
  }

  # ネットワーク制限:
  # - 既定 Deny で外部からの直接アクセスをブロック
  # - bypass で AzureServices/Logging/Metrics を許可 → Network Watcher Flow Logs と
  #   Front Door 診断ログの書き込みはこれで通る (これらは Azure サービス経由)
  # - 開発者からの直接参照 (Azure Portal / Storage Explorer) は ip_rules で許可
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices", "Logging", "Metrics"]
    ip_rules       = var.local-pc-ip-addresses
  }
}

# ログ保管コスト最適化: 30日後にCool、180日後にArchiveへ移行
# AWS側 S3 の Standard → Standard-IA → Glacier 構成と同様
resource "azurerm_storage_management_policy" "logs" {
  storage_account_id = azurerm_storage_account.logs.id

  rule {
    name    = "tiering"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 31
        tier_to_archive_after_days_since_modification_greater_than = 365
      }
    }
  }
}
