# Log Analytics 保存済みクエリ (AWS の Athena ワークグループ + Glueテーブル相当)
#
# AWS 側は S3 にログを置いて Glue カタログ + partition projection で Athena から SQL で参照する構成。
# Azure 側は Log Analytics Workspace にログを集約し、KQL で同等の分析を行う。
# 代表的なクエリをここで宣言的に保存しておくことで、運用時のクエリ立ち上げを高速化する。

# VNet Flow Logs (Traffic Analytics): 直近1時間の宛先別バイト数 TOP10
# AWS側 athena_vpc_flow_logs.tf と同じユースケース(誰がどこへ大量送信しているか)
# テーブル名: Traffic Analytics が Log Analytics に書き込む既定テーブルは AzureNetworkAnalytics_CL
resource "azurerm_log_analytics_saved_search" "vnet_flow_top_destinations" {
  name                       = "${var.app-name}-${var.environment}-vnet-flow-top-destinations"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.app_logs.id
  category                   = "VNetFlowLogs"
  display_name               = "VNet Flow: 宛先別バイト数 TOP10 (直近1h)"
  query                      = <<-KQL
    AzureNetworkAnalytics_CL
    | where SubType_s == "FlowLog"
    | where TimeGenerated > ago(1h)
    | summarize TotalBytes = sum(toreal(FlowCount_d) * toreal(coalesce(InboundBytes_d, 0.0) + coalesce(OutboundBytes_d, 0.0))) by DestIP_s
    | top 10 by TotalBytes desc
  KQL
}

# VNet Flow Logs: 拒否(Deny) されたフロー一覧 (直近24h)
resource "azurerm_log_analytics_saved_search" "vnet_flow_denied" {
  name                       = "${var.app-name}-${var.environment}-vnet-flow-denied"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.app_logs.id
  category                   = "VNetFlowLogs"
  display_name               = "VNet Flow: 拒否フロー (直近24h)"
  query                      = <<-KQL
    AzureNetworkAnalytics_CL
    | where SubType_s == "FlowLog"
    | where TimeGenerated > ago(24h)
    | where FlowStatus_s == "D"
    | project TimeGenerated, SrcIP_s, DestIP_s, DestPort_d, L7Protocol_s, FlowDirection_s
    | order by TimeGenerated desc
  KQL
}

# Front Door アクセスログ: ステータスコード分布 (直近1h)
# AWS側 athena_cloudfront_logs.tf と同じユースケース(sc_status の集計)
# diagnostic setting で log_analytics_destination_type = "Dedicated" を指定しているため、
# 専用テーブル AFDAccessLogs から参照する
resource "azurerm_log_analytics_saved_search" "frontdoor_status_distribution" {
  name                       = "${var.app-name}-${var.environment}-frontdoor-status-distribution"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.app_logs.id
  category                   = "FrontDoor"
  display_name               = "Front Door: ステータスコード分布 (直近1h)"
  query                      = <<-KQL
    AFDAccessLogs
    | where TimeGenerated > ago(1h)
    | summarize Count = count() by HttpStatusCode
    | order by Count desc
  KQL
}

# Front Door アクセスログ: 4xx/5xx エラーパス TOP20 (直近24h)
resource "azurerm_log_analytics_saved_search" "frontdoor_error_paths" {
  name                       = "${var.app-name}-${var.environment}-frontdoor-error-paths"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.app_logs.id
  category                   = "FrontDoor"
  display_name               = "Front Door: 4xx/5xx エラーパス TOP20 (直近24h)"
  query                      = <<-KQL
    AFDAccessLogs
    | where TimeGenerated > ago(24h)
    | where HttpStatusCode >= 400
    | summarize Count = count() by RequestUri, HttpStatusCode
    | top 20 by Count desc
  KQL
}

# Container Apps コンソールログ: ERROR レベル抽出 (直近1h)
# AWS側 ECS ログ (athena_ecs_logs.tf) と同じ "アプリ層の異常検知" 用途
# Container Apps Environment の log_analytics_workspace_id 経由で
# 自動的に ContainerAppConsoleLogs_CL テーブルに格納される
resource "azurerm_log_analytics_saved_search" "containerapp_console_errors" {
  name                       = "${var.app-name}-${var.environment}-containerapp-console-errors"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.app_logs.id
  category                   = "ContainerApp"
  display_name               = "Container App: コンソールERROR (直近1h)"
  query                      = <<-KQL
    ContainerAppConsoleLogs_CL
    | where TimeGenerated > ago(1h)
    | where Log_s has_any ("ERROR", "Error", "error")
    | project TimeGenerated, ContainerAppName_s, ContainerName_s, RevisionName_s, Log_s
    | order by TimeGenerated desc
  KQL
}

# Container Apps システムログ: リビジョン作成/起動失敗等のシステムイベント (直近24h)
resource "azurerm_log_analytics_saved_search" "containerapp_system_events" {
  name                       = "${var.app-name}-${var.environment}-containerapp-system-events"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.app_logs.id
  category                   = "ContainerApp"
  display_name               = "Container App: システムイベント (直近24h)"
  query                      = <<-KQL
    ContainerAppSystemLogs_CL
    | where TimeGenerated > ago(24h)
    | project TimeGenerated, ContainerAppName_s, Reason_s, Type_s, Log_s
    | order by TimeGenerated desc
  KQL
}

# Container App / Front Door の HTTP 5xx 分析は Front Door 側の AFDAccessLogs を使用
# (バックエンド単体の HTTP アクセスログは Container Apps 標準では出力されないため、
# upstream の Front Door ログでカバーする。 別途 azurerm_log_analytics_saved_search.frontdoor_error_paths を参照)
