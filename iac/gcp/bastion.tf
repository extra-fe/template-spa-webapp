# Bastion VM: AWS の EC2 Bastion + Session Manager 相当
# - IAP TCP forwarding 経由で SSH 接続 (gcloud compute ssh --tunnel-through-iap)
# - Cloud SQL Private IP に対する psql ポートフォワード等で利用
# - パブリック IP なし、firewall は 35.235.240.0/20 (IAP) からのみ SSH 許可

# Bastion 用 SA
resource "google_service_account" "bastion" {
  account_id   = "${var.app-name}-${var.environment}-bastion"
  display_name = "Bastion VM SA for ${var.app-name}-${var.environment}"
}

# Cloud SQL クライアント権限 (psql からの接続でも有用)
resource "google_project_iam_member" "bastion_sql_client" {
  project = var.gcp-project-id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.bastion.email}"
}

# Secret Manager 参照権限 (運用時に DATABASE_URL を取得するため)
resource "google_project_iam_member" "bastion_secret_accessor" {
  project = var.gcp-project-id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.bastion.email}"
}

# Cloud Logging への書き込み権限
resource "google_project_iam_member" "bastion_logwriter" {
  project = var.gcp-project-id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.bastion.email}"
}

# Bastion VM 本体
# IAP TCP forwarding 経由で SSH するため public IP は付与しない
resource "google_compute_instance" "bastion" {
  name         = "${var.app-name}-${var.environment}-bastion"
  machine_type = "e2-micro"
  zone         = var.gcp-zone

  tags = ["bastion"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30
      type  = "pd-balanced"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.primary.name
    # public IP 無し (IAP TCP forwarding を経由するため)
  }

  service_account {
    email  = google_service_account.bastion.email
    scopes = ["cloud-platform"]
  }

  # cloud-sql-proxy / postgresql-client を事前インストールしておく
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -eux
    apt-get update
    apt-get install -y postgresql-client wget
    wget -qO /usr/local/bin/cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.11.4/cloud-sql-proxy.linux.amd64
    chmod +x /usr/local/bin/cloud-sql-proxy
  EOT

  # 自動停止対象として扱えるよう、起動順序の依存関係を明示
  depends_on = [
    google_compute_router_nat.nat,
    google_service_networking_connection.psa,
  ]
}

# 任意の IAM ユーザ/グループに Bastion への IAP TCP 接続権限を付与するための
# IAM ロールバインディングは Terraform 外で管理 (環境ごとに変動するため)。
# 必要に応じて roles/iap.tunnelResourceAccessor を VM スコープで付与すること。
