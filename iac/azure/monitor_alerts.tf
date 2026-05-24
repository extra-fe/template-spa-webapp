# Azure Monitor メトリックアラート集約: Container App / PostgreSQL Flexible Server の異常検知
#
# AWS 側 cloudwatch_alarms.tf の Azure 等価実装:
# - 通知先 SNS Topic     → Action Group (本ファイルで作成)
# - CloudWatch Alarm     → azurerm_monitor_metric_alert
# - サブスクライバ(メール等)は本Terraformでは作成せず、Azure Portal から手動登録する想定
#
# 注意:
# - Container App のメトリックは Microsoft.App/containerApps 名前空間
#   利用率パーセントの指標が存在しないため、絶対値 (Nanocores / Bytes) と Restarts/Replicas で監視
# - PostgreSQL Flexible Server は AWS Aurora Serverless v2 とは違い ACU 連動指標が無いため、
#   素直に cpu_percent / memory_percent / storage_percent / active_connections を使う

locals {
  alert_eval_window_minutes = "PT5M" # 評価ウィンドウ (5分)
  alert_freq_minutes        = "PT1M" # 評価頻度 (1分)
  alert_cpu_threshold_pct   = 80     # PostgreSQL CPU 使用率しきい値
  alert_memory_util_pct     = 80     # PostgreSQL メモリ使用率しきい値
  alert_storage_util_pct    = 80     # PostgreSQL ストレージ使用率しきい値
  alert_connections_count   = 70     # PostgreSQL アクティブ接続数しきい値 (B_Standard_B1ms 最大200弱)

  # Container App リソース割り当て (cpu=0.5, memory=1Gi) に対するしきい値
  # cpu=0.5 vCPU = 5億 nanocores → 80% = 4億 nanocores
  alert_containerapp_cpu_nanocores = 400000000 # CPU 使用率 80% (= 0.4 vCPU)
  alert_containerapp_memory_bytes  = 858993459 # メモリ 80% of 1 GiB (= 約 819 MiB)
  alert_containerapp_restart_count = 3         # 5分以内に 3回以上 restart → 異常
}

# 全アラーム共通の通知先 Action Group
# Email/Slack(WebHook)/Function 等は Azure Portal から手動登録する
resource "azurerm_monitor_action_group" "alarms" {
  name                = "${var.app-name}-${var.environment}-alarms"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "alarms"
}

# ---------- Container App ----------
# 指標は Microsoft.App/containerApps 名前空間。
# CPU/メモリは絶対値 (nanocores / bytes)、Restarts はリビジョン単位の再起動回数。

# Container App CPU 使用量 > 0.4 vCPU (= 割当 0.5 vCPU に対する 80%)
resource "azurerm_monitor_metric_alert" "containerapp_cpu_high" {
  name                = "${var.app-name}-${var.environment}-containerapp-cpu-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_container_app.app.id]
  description         = "Container App の CPU 使用量が 0.4 vCPU (割当 0.5 の 80%) を超過"
  severity            = 2
  frequency           = local.alert_freq_minutes
  window_size         = local.alert_eval_window_minutes

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "UsageNanoCores"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = local.alert_containerapp_cpu_nanocores
  }

  action {
    action_group_id = azurerm_monitor_action_group.alarms.id
  }
}

# Container App メモリ使用量 > 819 MiB (= 割当 1 GiB の 80%)
resource "azurerm_monitor_metric_alert" "containerapp_memory_high" {
  name                = "${var.app-name}-${var.environment}-containerapp-memory-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_container_app.app.id]
  description         = "Container App のメモリ使用量が 819 MiB (割当 1 GiB の 80%) を超過"
  severity            = 2
  frequency           = local.alert_freq_minutes
  window_size         = local.alert_eval_window_minutes

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "WorkingSetBytes"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = local.alert_containerapp_memory_bytes
  }

  action {
    action_group_id = azurerm_monitor_action_group.alarms.id
  }
}

# Container App: 5分以内に Restart が ${alert_containerapp_restart_count} 回以上発生
# クラッシュループ検知 (App Service には無かったが、Container Apps では一般的な監視項目)
resource "azurerm_monitor_metric_alert" "containerapp_restarts_high" {
  name                = "${var.app-name}-${var.environment}-containerapp-restarts-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_container_app.app.id]
  description         = "Container App のレプリカ再起動が 5分間に ${local.alert_containerapp_restart_count} 回以上発生(クラッシュループ疑い)"
  severity            = 1 # 起動失敗系は致命的なので Warning(2) より重く
  frequency           = local.alert_freq_minutes
  window_size         = local.alert_eval_window_minutes

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "RestartCount"
    aggregation      = "Total"
    operator         = "GreaterThanOrEqual"
    threshold        = local.alert_containerapp_restart_count
  }

  action {
    action_group_id = azurerm_monitor_action_group.alarms.id
  }
}

# ---------- PostgreSQL Flexible Server ----------
# 指標は Microsoft.DBforPostgreSQL/flexibleServers 名前空間。

# PostgreSQL CPU 使用率 > 80%
resource "azurerm_monitor_metric_alert" "postgres_cpu_high" {
  name                = "${var.app-name}-${var.environment}-postgres-cpu-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_postgresql_flexible_server.db_server.id]
  description         = "PostgreSQL Flexible Server の CPU 使用率が ${local.alert_cpu_threshold_pct}% を超過"
  severity            = 2
  frequency           = local.alert_freq_minutes
  window_size         = local.alert_eval_window_minutes

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = local.alert_cpu_threshold_pct
  }

  action {
    action_group_id = azurerm_monitor_action_group.alarms.id
  }
}

# PostgreSQL メモリ使用率 > 80%
resource "azurerm_monitor_metric_alert" "postgres_memory_high" {
  name                = "${var.app-name}-${var.environment}-postgres-memory-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_postgresql_flexible_server.db_server.id]
  description         = "PostgreSQL Flexible Server のメモリ使用率が ${local.alert_memory_util_pct}% を超過"
  severity            = 2
  frequency           = local.alert_freq_minutes
  window_size         = local.alert_eval_window_minutes

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "memory_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = local.alert_memory_util_pct
  }

  action {
    action_group_id = azurerm_monitor_action_group.alarms.id
  }
}

# PostgreSQL ストレージ使用率 > 80%
# Aurora と違いストレージは自動拡張しないため "残量低下" を直接検知する
resource "azurerm_monitor_metric_alert" "postgres_storage_high" {
  name                = "${var.app-name}-${var.environment}-postgres-storage-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_postgresql_flexible_server.db_server.id]
  description         = "PostgreSQL Flexible Server のストレージ使用率が ${local.alert_storage_util_pct}% を超過"
  severity            = 1 # 容量枯渇は即書き込み停止につながるため Warning(2) より重く
  frequency           = local.alert_freq_minutes
  window_size         = local.alert_eval_window_minutes

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "storage_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = local.alert_storage_util_pct
  }

  action {
    action_group_id = azurerm_monitor_action_group.alarms.id
  }
}

# PostgreSQL アクティブ接続数 > 70
# B_Standard_B1ms の max_connections は標準 200 弱。70 は早めの警告ライン。
resource "azurerm_monitor_metric_alert" "postgres_connections_high" {
  name                = "${var.app-name}-${var.environment}-postgres-connections-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_postgresql_flexible_server.db_server.id]
  description         = "PostgreSQL アクティブ接続数が ${local.alert_connections_count} を超過"
  severity            = 2
  frequency           = local.alert_freq_minutes
  window_size         = local.alert_eval_window_minutes

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "active_connections"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = local.alert_connections_count
  }

  action {
    action_group_id = azurerm_monitor_action_group.alarms.id
  }
}
