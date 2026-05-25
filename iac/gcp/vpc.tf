# GCP プロジェクトで利用する API を有効化
# AWS では暗黙的に有効だが、GCP では事前有効化が必須
resource "google_project_service" "services" {
  for_each = toset([
    "compute.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "vpcaccess.googleapis.com",
    "servicenetworking.googleapis.com",
    "cloudbuild.googleapis.com",
    "clouddeploy.googleapis.com",
    "iap.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudscheduler.googleapis.com",
    "workflows.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "cloudkms.googleapis.com",
  ])
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}

# API 有効化の伝播待ち
# google_project_service の create が成功した直後にも、依存サービス
# (compute.googleapis.com 等) の有効化が GCP 全体に伝播するまで 30-120 秒かかる。
# この sleep を挟まないと "API not used / disabled" エラーで初回 apply が失敗する。
resource "time_sleep" "wait_for_apis" {
  depends_on      = [google_project_service.services]
  create_duration = "60s"
}

# Cloud CDN の cache fill サービスエージェント SA を先に作成
# (Backend Bucket への IAM 付与より前にこの SA を存在させる必要がある)
resource "google_project_service_identity" "compute" {
  provider = google-beta
  project  = var.gcp-project-id
  service  = "compute.googleapis.com"

  depends_on = [time_sleep.wait_for_apis]
}

# Cloud Monitoring の通知用 SA を先に作成
resource "google_project_service_identity" "monitoring" {
  provider = google-beta
  project  = var.gcp-project-id
  service  = "monitoring.googleapis.com"

  depends_on = [time_sleep.wait_for_apis]
}

# アプリ全体を収容する VPC (auto subnet を無効化して明示的にサブネットを定義)
resource "google_compute_network" "vpc" {
  name                            = "${var.app-name}-${var.environment}"
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false

  depends_on = [time_sleep.wait_for_apis]
}

# プライマリサブネット: Bastion 等のリソース配置先
# Private Google Access を有効化することで NAT 経由せず GCP API に到達できる
# (AWS の VPC Endpoint 相当)
resource "google_compute_subnetwork" "primary" {
  name                     = "${var.app-name}-${var.environment}-primary"
  ip_cidr_range            = var.subnet_primary_cidr_block
  region                   = var.gcp-region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  # VPC Flow Logs: AWS の VPC Flow Logs 相当 (Cloud Logging へ出力)
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Serverless VPC Access コネクタ用サブネット (/28 必須・コネクタ専用)
resource "google_compute_subnetwork" "connector" {
  name                     = "${var.app-name}-${var.environment}-connector"
  ip_cidr_range            = var.subnet_connector_cidr_block
  region                   = var.gcp-region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# Cloud Router: Cloud NAT のための論理ルータ
resource "google_compute_router" "nat" {
  name    = "${var.app-name}-${var.environment}-router"
  region  = var.gcp-region
  network = google_compute_network.vpc.id
}

# Cloud NAT: AWS の Regional NAT Gateway 相当
# - VPC 内インスタンスのアウトバウンドインターネット通信を NAT
# - IP は自動払い出し
resource "google_compute_router_nat" "nat" {
  name                               = "${var.app-name}-${var.environment}-nat"
  router                             = google_compute_router.nat.name
  region                             = var.gcp-region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Serverless VPC Access コネクタ: Cloud Run → VPC へのトラフィックを通す
# AWS の ECS Fargate awsvpc モード相当 (Cloud SQL Private IP に到達するため)
resource "google_vpc_access_connector" "connector" {
  name          = "${var.app-name}-${var.environment}"
  region        = var.gcp-region
  subnet {
    name = google_compute_subnetwork.connector.name
  }
  machine_type  = "e2-micro"
  min_instances = 2
  max_instances = 3

  depends_on = [google_project_service.services]
}

# Private Service Access 用 IP レンジ予約
# Cloud SQL Private IP 接続に必要 (Google マネージドプロデューササービスへの VPC ピアリングで利用)
resource "google_compute_global_address" "psa_range" {
  name          = "${var.app-name}-${var.environment}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = tonumber(split("/", var.psa_range_cidr_block)[1])
  address       = split("/", var.psa_range_cidr_block)[0]
  network       = google_compute_network.vpc.id

  depends_on = [time_sleep.wait_for_apis]
}

# Service Networking 接続: Cloud SQL 等のマネージドサービスを Private IP で使うためのピアリング
resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]

  depends_on = [google_project_service.services]
}
