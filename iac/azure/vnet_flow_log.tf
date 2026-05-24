# VNet Flow Logs: AWS の VPC Flow Logs 相当
# - Network Watcher を経由して、VNet 配下の全トラフィックを Storage Account に記録
# - 分析用に Traffic Analytics で Log Analytics Workspace にも集約 (Athena相当のKQL分析の入口)

# Network Watcher
# 既定では Azure が NetworkWatcherRG/NetworkWatcher_<region> を自動作成するが、
# 本テンプレートでは自前のRGに明示的に作成して構成を自己完結させる(複数併存可)
resource "azurerm_network_watcher" "nw" {
  name                = "${var.app-name}-${var.environment}-nw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# VNet Flow Log (旧 NSG Flow Log の後継)
# - target_resource_id に VNet を指定すると配下サブネット/NIC を一括カバー
# - retention は Storage 側のライフサイクル(storage-account-logs.tf)と二重管理しない
resource "azurerm_network_watcher_flow_log" "vnet" {
  name                 = "${var.app-name}-${var.environment}-vnet-flow-log"
  network_watcher_name = azurerm_network_watcher.nw.name
  resource_group_name  = azurerm_network_watcher.nw.resource_group_name
  location             = azurerm_resource_group.rg.location

  target_resource_id = azurerm_virtual_network.vnet.id
  storage_account_id = azurerm_storage_account.logs.id
  enabled            = true
  version            = 2

  retention_policy {
    enabled = true
    days    = 30
  }

  # Traffic Analytics: フローログを Log Analytics Workspace に取り込んで KQL で分析
  # AWS 側の Athena + partition projection と同等の "クエリで横断分析" を実現
  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.app_logs.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.app_logs.location
    workspace_resource_id = azurerm_log_analytics_workspace.app_logs.id
    interval_in_minutes   = 10
  }
}
