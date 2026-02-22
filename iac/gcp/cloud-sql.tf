## DB パスワード生成
resource "random_string" "db-password" {
  length  = 12
  upper   = true
  lower   = true
  numeric = true
  special = false
}

locals {
  db-password  = random_string.db-password.result
  db-encoded-pw = urlencode(local.db-password)
  database-url = join("", [
    "postgresql://",
    "${google_sql_user.default.name}",
    ":",
    "${local.db-encoded-pw}",
    "@",
    "${google_sql_database_instance.db.private_ip_address}",
    ":",
    "5432",
    "/",
    "${google_sql_database.default.name}",
    "?",
    "sslmode=require"
  ])
}

## Cloud SQL PostgreSQL インスタンス
resource "google_sql_database_instance" "db" {
  name                = "${var.app-name}-${var.environment}-db"
  database_version    = "POSTGRES_16"
  region              = var.region
  deletion_protection = false

  settings {
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = false
      start_time                     = "03:00"
      backup_retention_settings {
        retained_backups = 7
      }
    }

    maintenance_window {
      day  = 7
      hour = 3
    }
  }

  depends_on = [google_service_networking_connection.private-vpc-connection]
}

## データベース
resource "google_sql_database" "default" {
  name     = "${var.app-name}-${var.environment}-db"
  instance = google_sql_database_instance.db.name
}

## データベースユーザー
resource "google_sql_user" "default" {
  name     = "${var.app-name}${var.environment}admin"
  instance = google_sql_database_instance.db.name
  password = local.db-password
}
