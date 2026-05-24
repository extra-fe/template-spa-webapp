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

# 環境専用の random_string
# Storage Account / ACR / Key Vault が共有している random_string.random とは分離している。
# 理由: 環境が ScheduledForDelete でスタックした際、 random_string.random を taint すると
# Storage 等の全リソース名まで巻き込んで destroy + recreate が走ってしまうため、
# 環境名サフィックスだけ単独で再生成できるようにする
resource "random_string" "container_apps_env" {
  length  = 4
  upper   = false
  lower   = true
  numeric = true
  special = false
}

# 環境名に random suffix を付与している理由:
# Container Apps 環境は削除に長時間 (数時間〜) かかることがあり、 削除中 (ScheduledForDelete) は
# 同名で再作成できない。 suffix を付けておくと、 万一スタックしても他のリソース名を変えずに
# Terraform の差し替えで新環境を作れる
resource "azurerm_container_app_environment" "env" {
  name                       = "${var.app-name}-${var.environment}-cae-${random_string.container_apps_env.result}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.app_logs.id

  infrastructure_subnet_id       = azurerm_subnet.container_apps_v2.id
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

  # DATABASE-URL は Container Apps 内蔵の secret store に直接格納する。
  #
  # 当初は Key Vault 参照 (key_vault_secret_id) を使っていたが、 KV の network_acls を
  # 有効化すると Container Apps platform からの secret fetch がブロックされる。
  # Microsoft ドキュメントは環境の static_ip_address を ip_rules に追加することで解決
  # するとあるが、 実際には CA platform は VNet egress 外の Microsoft 内部経路で fetch
  # するため allowlist が効かないケースがある。
  #
  # 対処として:
  # - DATABASE-URL は Container Apps secret store に直接埋め込む (azure_database.tf の
  #   local.database_url を流用)
  # - KV の DATABASE-URL secret 自体は残置 (key-vault.tf 参照) — 他の用途のために。
  # - KV network_acls はそのまま維持され、 他の secret (auth0 等) の保護は継続する
  secret {
    name  = "database-url"
    value = local.database_url
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
        value = "true"
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

  # ACR Pull 権限が先に確立してから Container App を作るための明示的依存
  # (KV Access Policy は不要になった — secret は KV ではなく CA secret store 経由)
  depends_on = [
    azurerm_role_assignment.container_app_acr_pull,
  ]

  # GitHub Actions からのデプロイで image tag が更新されるため、diff を無視
  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
    ]
  }
}

# Container Apps のコンソール/システムログ:
# 個別 Container App リソースには ContainerAppConsoleLogs / ContainerAppSystemLogs カテゴリを
# 紐付けられない仕様 (環境 = managedEnvironments のみ対応)。
# 本テンプレートでは azurerm_container_app_environment.env に log_analytics_workspace_id を
# 設定済みのため、 環境経由で自動的に Log Analytics の
# ContainerAppConsoleLogs_CL / ContainerAppSystemLogs_CL テーブルへログが流れる。
# したがって Container App 単体への diagnostic_setting は不要 (重複させると二重課金)。
#
# メトリックは Azure Monitor の標準メトリックストアへ自動送信され、 monitor_alerts.tf の
# azurerm_monitor_metric_alert から直接参照可能。
