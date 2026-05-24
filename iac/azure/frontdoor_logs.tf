# Front Door の診断ログ設定
# AWS の CloudFront アクセスログ (v2 CW Logs Delivery, JSON) と同等の役割
# - FrontDoorAccessLog       : リクエスト単位のアクセスログ (Athena/KQL 分析対象)
# - FrontDoorHealthProbeLog  : Origin ヘルスプローブの結果
# 出力先は Storage(長期保管) と Log Analytics(KQL分析) の両方
#   ※ Standard SKU では WAF ログ (FrontDoorWebApplicationFirewallLog) は存在しない (Premium 専用)
resource "azurerm_monitor_diagnostic_setting" "frontdoor" {
  name                           = "${var.app-name}-${var.environment}-frontdoor-diag"
  target_resource_id             = azurerm_cdn_frontdoor_profile.cdn.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.app_logs.id
  log_analytics_destination_type = "Dedicated" # リソース別テーブル(AFDAccessLogs 等)に出力 → KQL クエリが簡潔に
  storage_account_id             = azurerm_storage_account.logs.id

  enabled_log {
    category = "FrontDoorAccessLog"
  }

  enabled_log {
    category = "FrontDoorHealthProbeLog"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
