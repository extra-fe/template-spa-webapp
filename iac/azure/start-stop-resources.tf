# 自動起動・停止 (AWS の EventBridge Scheduler + Step Functions 相当)
#
# 実装方式: Azure Automation Account + PowerShell Runbook + Schedule
# - Step Functions に近い "順序付きシーケンス" を PowerShell スクリプト内で表現
# - Managed Identity に Resource Group の Contributor を付与し、App Service / PostgreSQL / VM を操作
# - 起動側 (auto_start) は AWS と同じく既定で「無効」(job_schedule を作成しない)

# auto_start を有効化するかどうか
# AWS 側 state="DISABLED" と同様、既定では停止スケジュールのみ動作させる
variable "auto-start-enabled" {
  type        = bool
  default     = false
  description = "true にすると土日 05:00 JST の自動起動スケジュールが有効化される"
}

resource "azurerm_automation_account" "auto" {
  name                = "${var.app-name}-${var.environment}-automation"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }
}

# Runbook の Managed Identity に Resource Group の Contributor 権限を付与
# (Start/Stop-AzWebApp, Start/Stop-AzPostgreSqlFlexibleServer, Start/Stop-AzVM 全てに必要)
resource "azurerm_role_assignment" "automation_contributor" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.auto.identity[0].principal_id
}

# ---------- Runbook: auto_stop ----------
# 停止順序: PostgreSQL → Bastion VM
# (Container App は min_replicas=0 で自動 scale-to-zero されるため停止操作不要)
resource "azurerm_automation_runbook" "auto_stop" {
  name                    = "${var.app-name}-${var.environment}-auto-stop"
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.auto.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"
  description             = "${var.app-name}-${var.environment} の PostgreSQL / Bastion を停止 (Container App は自動 scale-to-zero)"

  content = <<-EOT
    $ErrorActionPreference = "Stop"

    # Managed Identity でログイン
    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-AzAccount -Identity | Out-Null
    Set-AzContext -SubscriptionId "${var.azure-subscription-id}" | Out-Null

    $rg          = "${azurerm_resource_group.rg.name}"
    $pgName      = "${azurerm_postgresql_flexible_server.db_server.name}"
    $vmName      = "${azurerm_linux_virtual_machine.bastion_vm.name}"

    Write-Output "[1/2] Stop PostgreSQL Flexible Server: $pgName"
    Stop-AzPostgreSqlFlexibleServer -ResourceGroupName $rg -Name $pgName | Out-Null

    Write-Output "[2/2] Stop Bastion VM: $vmName"
    Stop-AzVM -ResourceGroupName $rg -Name $vmName -Force | Out-Null

    Write-Output "auto-stop completed. (Container App will scale to zero automatically when idle)"
  EOT
}

# ---------- Runbook: auto_start ----------
# 起動順序: Bastion VM → PostgreSQL
# (Container App は受信リクエスト発生時に自動 scale-up するため起動操作不要)
resource "azurerm_automation_runbook" "auto_start" {
  name                    = "${var.app-name}-${var.environment}-auto-start"
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.auto.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"
  description             = "${var.app-name}-${var.environment} の Bastion / PostgreSQL を起動 (Container App はリクエスト時に自動起動)"

  content = <<-EOT
    $ErrorActionPreference = "Stop"

    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-AzAccount -Identity | Out-Null
    Set-AzContext -SubscriptionId "${var.azure-subscription-id}" | Out-Null

    $rg          = "${azurerm_resource_group.rg.name}"
    $pgName      = "${azurerm_postgresql_flexible_server.db_server.name}"
    $vmName      = "${azurerm_linux_virtual_machine.bastion_vm.name}"

    Write-Output "[1/2] Start Bastion VM: $vmName"
    Start-AzVM -ResourceGroupName $rg -Name $vmName | Out-Null

    Write-Output "[2/2] Start PostgreSQL Flexible Server: $pgName"
    Start-AzPostgreSqlFlexibleServer -ResourceGroupName $rg -Name $pgName | Out-Null

    Write-Output "auto-start completed. (Container App will start on first request)"
  EOT
}

# ---------- Schedule: 毎日 21:00 JST 停止 ----------
# AWS 側: cron(0 21 * * ? *) Asia/Tokyo
resource "azurerm_automation_schedule" "auto_stop" {
  name                    = "auto-stop-${var.app-name}-${var.environment}"
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.auto.name
  frequency               = "Day"
  interval                = 1
  timezone                = "Asia/Tokyo"
  # 翌日の 21:00 JST から発火開始 (start_time は未来である必要があるため余裕を持って遠未来日を指定)
  start_time  = "2030-01-01T21:00:00+09:00"
  description = "毎日 21:00 JST に停止"
}

# ---------- Schedule: 土日 05:00 JST 起動 ----------
# AWS 側: cron(0 5 ? * SAT,SUN *) Asia/Tokyo
resource "azurerm_automation_schedule" "auto_start" {
  name                    = "auto-start-${var.app-name}-${var.environment}"
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.auto.name
  frequency               = "Week"
  interval                = 1
  timezone                = "Asia/Tokyo"
  week_days               = ["Saturday", "Sunday"]
  start_time              = "2030-01-04T05:00:00+09:00" # 2030-01-04 は金曜なので翌5日(土)が初回発火
  description             = "土日 05:00 JST に起動"
}

# ---------- スケジュールと Runbook を紐付け ----------
# Azure Automation には Schedule の "DISABLED" 状態が無いため、
# AWS の state="DISABLED" と等価な動作は job_schedule (関連付け) を作らないことで実現する
resource "azurerm_automation_job_schedule" "auto_stop" {
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.auto.name
  schedule_name           = azurerm_automation_schedule.auto_stop.name
  runbook_name            = azurerm_automation_runbook.auto_stop.name
}

resource "azurerm_automation_job_schedule" "auto_start" {
  count                   = var.auto-start-enabled ? 1 : 0
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.auto.name
  schedule_name           = azurerm_automation_schedule.auto_start.name
  runbook_name            = azurerm_automation_runbook.auto_start.name
}
