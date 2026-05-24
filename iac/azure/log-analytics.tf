# Log Analytics ワークスペース
# 用途: Container App / Front Door / VNet Flow Logs / その他診断ログの取込み先
# - Athena 相当の KQL クエリ実行基盤 (log_analytics_queries.tf 参照)
# - Container Apps Environment の標準ログ出力先としても利用
resource "azurerm_log_analytics_workspace" "app_logs" {
  name                = "${var.app-name}-${var.environment}-logws"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}
