# GCP VPC Firewall ルール: AWS Security Group 相当
# GCP の Firewall は VPC 単位で適用され、target tags / service accounts で対象を絞る
#
# AWS 側のルール構成:
#   ALB SG       <- CloudFront VPC Origin                : 80
#   ECS SG       <- ALB                                  : 3000
#   ECS SG  egress -> 443 / DB SG                        : NAT + DB
#   DB SG        <- ECS SG / Bastion                     : 5432
#   Bastion SG   <- 開発者IP                              : 0-65535
#   Bastion SG egress -> SSM endpoint / DB               : 443 / 5432
#
# GCP 側マッピング:
#   - ALB + CloudFront 相当: External Application LB + Cloud CDN は VPC firewall の対象外
#     (LB → Cloud Run は Serverless NEG 経由でマネージドネットワーク)
#   - Cloud Run → Cloud SQL は Serverless VPC Access コネクタ経由
#     コネクタ自身が source range として PSA range (Cloud SQL) へアクセスする
#   - Bastion は IAP TCP forwarding 専用 (35.235.240.0/20 から SSH)
#   - DB 接続は VPC Connector range / Bastion からのみ許可

# 全 ingress をデフォルト拒否 (GCP のデフォルトと同じだが明示)
# 不要トラフィックを遮断する保険として最低優先度で配置
resource "google_compute_firewall" "deny_all_ingress" {
  name      = "${var.app-name}-${var.environment}-deny-all-ingress"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"
  priority  = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

# Bastion への SSH を IAP TCP forwarding 経由でのみ許可
# AWS の SSM Session Manager 相当 (踏み台への直接 SSH は不要)
# IAP TCP forwarding の送信元 IP レンジは Google 固定の 35.235.240.0/20
resource "google_compute_firewall" "bastion_ssh_from_iap" {
  name      = "${var.app-name}-${var.environment}-bastion-ssh-from-iap"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["bastion"]
}

# Bastion からの egress: Cloud SQL Private IP (PSA range) への 5432 のみ
# GCP の Firewall は egress も target tags ベースで制御可能
resource "google_compute_firewall" "bastion_egress_db" {
  name      = "${var.app-name}-${var.environment}-bastion-egress-db"
  network   = google_compute_network.vpc.name
  direction = "EGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  destination_ranges = [var.psa_range_cidr_block]
  target_tags        = ["bastion"]
}

# Bastion からの egress: HTTPS (Cloud APIs / パッケージ更新)
resource "google_compute_firewall" "bastion_egress_https" {
  name      = "${var.app-name}-${var.environment}-bastion-egress-https"
  network   = google_compute_network.vpc.name
  direction = "EGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["bastion"]
}

# (任意) 開発者 PC IP からの 5432 直接接続を許可するルール
# 通常は IAP TCP forwarding 経由で Bastion → DB を推奨するため無効化が望ましい
resource "google_compute_firewall" "dev_pc_to_db" {
  count     = length(var.local-pc-ip-addresses) > 0 ? 1 : 0
  name      = "${var.app-name}-${var.environment}-devpc-to-db"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"
  priority  = 900

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = var.local-pc-ip-addresses
  # PSA range 内の Cloud SQL Private IP に届かせるため、target は指定せず PSA range 全体に到達可能とする
  # 注意: 通常は不要。bastion を経由する運用を推奨
}
