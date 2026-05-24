# Container Apps 環境 (Workload Profiles + Consumption profile, VNet 統合)
#
# 構成方針:
# - Workload Profiles 環境を採用 (Consumption-only 環境は新規は非推奨)
# - 既定の Consumption profile のみ使用 (Dedicated は今のところ不要 = 固定費 0)
# - VNet 統合: container_apps サブネット (/27) を infrastructure_subnet として割当
# - ingress は public (Front Door からアクセス可能)。
#   ※ Standard SKU の Front Door は Private Link 非対応のため backend は public ingress となる。
#      アプリ層で X-Azure-FDID ヘッダ検証を入れて Front Door 経由以外を拒否する想定。

# UserAssignedIdentity を Container App に紐付け
# 理由: SystemAssigned だと Key Vault Access Policy との間に循環依存が発生する
# (Container App 作成 → identity.principal_id 取得 → KV Access Policy 付与 → Container App が secret 参照可能)
# UserAssignedIdentity なら先に作って KV 権限を付与してから Container App に attach できる
resource "azurerm_user_assigned_identity" "container_app" {
  name                = "${var.app-name}-${var.environment}-app-uami"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# UAMI に ACR Pull 権限
resource "azurerm_role_assignment" "container_app_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.container_app.principal_id
}

resource "azurerm_container_app_environment" "env" {
  name                       = "${var.app-name}-${var.environment}-containerapps-env"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.app_logs.id

  infrastructure_subnet_id       = azurerm_subnet.container_apps.id
  internal_load_balancer_enabled = false # Front Door からアクセスするため public LB

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

# Container App 本体
# - revision_mode = "Single": dev 用途で簡素化 (Multiple は青緑/カナリア時に使う)
# - min_replicas = 0: アイドル時は scale-to-zero でコスト 0
# - max_replicas = 3: dev 上限の安全弁
# - registry: UAMI 経由で ACR Pull
# - secret: Key Vault の DATABASE-URL を UAMI で参照
resource "azurerm_container_app" "app" {
  name                         = "${var.app-name}-${var.environment}-app"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.container_app.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.container_app.id
  }

  secret {
    name                = "database-url"
    key_vault_secret_id = azurerm_key_vault_secret.postgre_flexible_server_connection_string.versionless_id
    identity            = azurerm_user_assigned_identity.container_app.id
  }

  template {
    min_replicas = 0
    max_replicas = 3

    container {
      name = "backend"
      # 初回 apply 時点では ACR にまだ backend イメージが push されていないため、
      # Microsoft 公式 Container Apps quickstart 画像をプレースホルダとして使用。
      # 以降は GitHub Actions が `az containerapp update --image` で更新し、
      # lifecycle.ignore_changes により Terraform 側からは差分扱いされない。
      image  = "mcr.microsoft.com/k8se/quickstart:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "PORT"
        value = tostring(var.api-expose-port)
      }
      env {
        name  = "LOG_LEVEL"
        value = "Debug"
      }
      env {
        name  = "CORS_ORIGIN"
        value = "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
      }
      env {
        name  = "CORS_METHODS"
        value = "GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS"
      }
      env {
        name  = "AUTH0_DOMAIN"
        value = var.auth0_domain
      }
      env {
        name  = "AUTH0_AUDIENCE"
        value = "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
      }
      env {
        name  = "AUTH_ENABLED"
        value = "false"
      }
      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }
      env {
        name  = "PRISMA_LOG_LEVEL"
        value = "query,info,warn,error"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = var.api-expose-port
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  # KV Access / ACR Pull 権限が先に確立してから Container App を作るための明示的依存
  depends_on = [
    azurerm_key_vault_access_policy.container_app_identity,
    azurerm_role_assignment.container_app_acr_pull,
  ]

  # GitHub Actions からのデプロイで image tag が更新されるため、diff を無視
  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
    ]
  }
}

# Container App 用の診断ログ設定 (App Service の HTTP/Console/AppLogs 相当)
# Container Apps では Console / System のログカテゴリが利用可能
resource "azurerm_monitor_diagnostic_setting" "container_app" {
  name                       = "${var.app-name}-${var.environment}-containerapp-diag"
  target_resource_id         = azurerm_container_app.app.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.app_logs.id

  enabled_log {
    category = "ContainerAppConsoleLogs"
  }

  enabled_log {
    category = "ContainerAppSystemLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
