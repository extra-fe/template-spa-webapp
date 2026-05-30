# Cloud SQL for PostgreSQL: AWS の Aurora Serverless v2 相当
# - Private IP のみ (Service Networking ピアリング経由)
# - 自動バックアップ + PITR
# - DB マスターパスワードはランダム生成、DATABASE_URL は Secret Manager に格納

# DB マスターパスワード: 16桁ランダム
resource "random_password" "db_password" {
  length  = 16
  special = false
}

# Cloud SQL インスタンス
# Aurora Serverless v2 のような ACU 自動スケーリングはないが、
# Cloud SQL のマシンタイプは variables.tf で調整可能
resource "google_sql_database_instance" "main" {
  name             = "${var.app-name}-${var.environment}-db"
  region           = var.gcp-region
  database_version = "POSTGRES_16"

  deletion_protection = false

  settings {
    tier              = var.db-tier
    # 新規プロジェクトでは ENTERPRISE_PLUS がデフォルトになり db-custom-* tier が使えないため
    # 明示的に ENTERPRISE edition を指定 (Aurora Serverless v2 と同等の従来 tier 体系)
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled                                   = false
      private_network                                = google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "17:00" # 02:00 JST (UTC-9)
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 18 # 03:00 JST
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = false
      record_client_address   = false
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"
    }
  }

  depends_on = [
    google_service_networking_connection.psa,
    google_project_service.services,
  ]
}

# DB
resource "google_sql_database" "app" {
  name     = replace("${var.app-name}${var.environment}db", "-", "")
  instance = google_sql_database_instance.main.name
}

# DB ユーザ
resource "google_sql_user" "app" {
  name     = replace("${var.app-name}${var.environment}dbadmin", "-", "")
  instance = google_sql_database_instance.main.name
  password = random_password.db_password.result
}

# DATABASE_URL を組み立て、Secret Manager に格納
# (Cloud Run の env から secret_key_ref で参照する)
locals {
  db_encoded_password = urlencode(random_password.db_password.result)
  database_url = join("", [
    "postgresql://",
    google_sql_user.app.name,
    ":",
    local.db_encoded_password,
    "@",
    google_sql_database_instance.main.private_ip_address,
    ":5432/",
    google_sql_database.app.name,
    "?sslmode=require",
    "&connection_limit=${var.db-connection-limit}",
    "&pool_timeout=${var.db-pool-timeout}",
  ])
}
