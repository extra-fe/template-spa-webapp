# Cloud Logging → BigQuery sink: AWS の Athena (Glue Catalog) 相当
# Cloud Logging はサービスログを構造化 JSON のまま吐き出すため、
# AWS のように RegexSerDe や partition projection を組む必要はない。
# BigQuery 側は use_partitioned_tables = true で日付パーティションテーブルを自動作成する。
#
# AWS との対応:
#   ALB アクセスログ (Glue table)   → LB request log sink → BigQuery
#   CloudFront アクセスログ          → LB request log sink (上記と同じ — LB が CDN を兼ねる)
#   ECS コンテナログ (Athena)        → Cloud Run コンテナログ sink → BigQuery
#   WAF ログ (Athena)                → Cloud Armor ログ sink → BigQuery
#   VPC Flow Logs (Athena)           → Compute Engine flow logs sink → BigQuery

# 共通: ログ専用 BigQuery データセット (テーブルは sink が動的に作成)
resource "google_bigquery_dataset" "lb_logs" {
  dataset_id  = replace("${var.app-name}_${var.environment}_lb_logs", "-", "_")
  location    = var.gcp-region
  description = "External Application LB request logs (CloudFront + ALB アクセスログ相当)"

  default_table_expiration_ms = 31536000000 # 365日
}

resource "google_bigquery_dataset" "cloud_run_logs" {
  dataset_id  = replace("${var.app-name}_${var.environment}_cloud_run_logs", "-", "_")
  location    = var.gcp-region
  description = "Cloud Run コンテナログ (AWS ECS / FireLens 相当)"

  default_table_expiration_ms = 31536000000
}

resource "google_bigquery_dataset" "armor_logs" {
  dataset_id  = replace("${var.app-name}_${var.environment}_armor_logs", "-", "_")
  location    = var.gcp-region
  description = "Cloud Armor (WAF) ログ"

  default_table_expiration_ms = 31536000000
}

resource "google_bigquery_dataset" "vpc_flow_logs" {
  dataset_id  = replace("${var.app-name}_${var.environment}_vpc_flow_logs", "-", "_")
  location    = var.gcp-region
  description = "VPC Flow Logs"

  default_table_expiration_ms = 31536000000
}

# ---------- LB アクセスログ ----------
# Cloud Logging で resource.type = "http_load_balancer" がエクスポート対象
resource "google_logging_project_sink" "lb_logs" {
  name        = "${var.app-name}-${var.environment}-lb-logs"
  destination = "bigquery.googleapis.com/projects/${var.gcp-project-id}/datasets/${google_bigquery_dataset.lb_logs.dataset_id}"

  filter = "resource.type=\"http_load_balancer\" AND resource.labels.url_map_name=\"${google_compute_url_map.main.name}\""

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_bigquery_dataset_iam_member" "lb_logs_writer" {
  dataset_id = google_bigquery_dataset.lb_logs.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.lb_logs.writer_identity
}

# ---------- Cloud Run コンテナログ ----------
resource "google_logging_project_sink" "cloud_run_logs" {
  name        = "${var.app-name}-${var.environment}-run-logs"
  destination = "bigquery.googleapis.com/projects/${var.gcp-project-id}/datasets/${google_bigquery_dataset.cloud_run_logs.dataset_id}"

  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.backend.name}\""

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_bigquery_dataset_iam_member" "cloud_run_logs_writer" {
  dataset_id = google_bigquery_dataset.cloud_run_logs.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.cloud_run_logs.writer_identity
}

# ---------- Cloud Armor (WAF) ログ ----------
# Cloud Armor のログは LB request log の jsonPayload.enforcedSecurityPolicy 等に紛れ込むが、
# 専用ストリーム (enforcedSecurityPolicy.name = "<policy name>") でフィルタしてエクスポート
resource "google_logging_project_sink" "armor_logs" {
  name        = "${var.app-name}-${var.environment}-armor-logs"
  destination = "bigquery.googleapis.com/projects/${var.gcp-project-id}/datasets/${google_bigquery_dataset.armor_logs.dataset_id}"

  filter = join(" AND ", [
    "resource.type=\"http_load_balancer\"",
    "jsonPayload.enforcedSecurityPolicy.name=\"${google_compute_security_policy.edge.name}\"",
  ])

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_bigquery_dataset_iam_member" "armor_logs_writer" {
  dataset_id = google_bigquery_dataset.armor_logs.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.armor_logs.writer_identity
}

# ---------- VPC Flow Logs ----------
# VPC Flow Logs は resource.type = "gce_subnetwork" でフィルタ
resource "google_logging_project_sink" "vpc_flow_logs" {
  name        = "${var.app-name}-${var.environment}-vpc-flow"
  destination = "bigquery.googleapis.com/projects/${var.gcp-project-id}/datasets/${google_bigquery_dataset.vpc_flow_logs.dataset_id}"

  filter = join(" AND ", [
    "resource.type=\"gce_subnetwork\"",
    "logName=\"projects/${var.gcp-project-id}/logs/compute.googleapis.com%2Fvpc_flows\"",
  ])

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_bigquery_dataset_iam_member" "vpc_flow_logs_writer" {
  dataset_id = google_bigquery_dataset.vpc_flow_logs.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.vpc_flow_logs.writer_identity
}
