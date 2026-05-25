# Cloud Run サービス: AWS の ECS Fargate + ALB Target Group 相当
# - サーバーレス、スケール 0〜N
# - Serverless VPC Access コネクタ経由で VPC 内の Cloud SQL Private IP に到達
# - イメージは Artifact Registry から pull
# - 環境変数 / シークレットは Secret Manager から注入

# Cloud Run サービス用のランタイム SA
# AWS の aws_iam_role.ecs_task 相当 (コンテナアプリ自身が AWS API を呼ぶときのロール)
resource "google_service_account" "cloud_run" {
  account_id   = "${var.app-name}-${var.environment}-run"
  display_name = "Cloud Run runtime SA for ${var.app-name}-${var.environment}"
}

# Secret Manager のシークレット参照権限
# AWS の execute_ecs_task の ssm:GetParameters 相当
resource "google_project_iam_member" "cloud_run_secret_accessor" {
  project = var.gcp-project-id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# Artifact Registry の pull 権限
# AWS の execute_ecs_task の ecr:* 相当
resource "google_artifact_registry_repository_iam_member" "cloud_run_ar_reader" {
  location   = google_artifact_registry_repository.backend.location
  repository = google_artifact_registry_repository.backend.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.cloud_run.email}"
}

# Cloud SQL クライアント権限 (Private IP 経由でも IAM 認証/接続性のため付与)
resource "google_project_iam_member" "cloud_run_sql_client" {
  project = var.gcp-project-id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# Cloud Logging への書き込み権限 (デフォルトで Cloud Run コンテナログが出力される)
resource "google_project_iam_member" "cloud_run_logwriter" {
  project = var.gcp-project-id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# Cloud Run サービス本体
resource "google_cloud_run_v2_service" "backend" {
  name                = "${var.app-name}-${var.environment}-service"
  location            = var.gcp-region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = false

  template {
    service_account = google_service_account.cloud_run.email

    # AWS タスク定義 CPU=256 / Memory=512 と同等規模の最小構成
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }

    # Serverless VPC Access コネクタ経由で VPC 内 Cloud SQL に到達
    # egress = PRIVATE_RANGES_ONLY: NAT を介さず VPC 内 Private IP のみコネクタへ
    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "${google_artifact_registry_repository.backend.location}-docker.pkg.dev/${var.gcp-project-id}/${google_artifact_registry_repository.backend.repository_id}/backend:latest"

      ports {
        container_port = var.api-expose-port
      }

      resources {
        cpu_idle = true
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      # ヘルスチェック (Cloud Run startup / liveness probe)
      startup_probe {
        http_get {
          path = var.health-check-path
          port = var.api-expose-port
        }
        initial_delay_seconds = 5
        period_seconds        = 10
        timeout_seconds       = 3
        failure_threshold     = 6
      }

      liveness_probe {
        http_get {
          path = var.health-check-path
          port = var.api-expose-port
        }
        period_seconds    = 30
        timeout_seconds   = 5
        failure_threshold = 3
      }

      # PORT は Cloud Run が自動的に container_port から設定するため明示不可
      # (システム予約環境変数)
      env {
        name  = "LOG_LEVEL"
        value = "debug"
      }
      env {
        name  = "AUTH0_DOMAIN"
        value = var.auth0_domain
      }
      env {
        name  = "AUTH0_AUDIENCE"
        value = local.public_url
      }
      env {
        name  = "CORS_ORIGIN"
        value = local.public_url
      }
      env {
        name  = "CORS_METHODS"
        value = "GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS"
      }
      env {
        name  = "AUTH_ENABLED"
        value = "true"
      }
      env {
        name  = "PRISMA_LOG_LEVEL"
        value = "query,info,warn,error"
      }
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_connection_string.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  # Cloud Build / Cloud Deploy で image を更新するため、image / scaling を ignore
  # AWS の aws_ecs_service の lifecycle.ignore_changes (task_definition) と同じ思想
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_project_iam_member.cloud_run_secret_accessor,
    google_artifact_registry_repository_iam_member.cloud_run_ar_reader,
  ]
}

# LB (Serverless NEG 経由) からの呼び出しのみを許可するため、Cloud Run の IAM Invoker を制御
# 注: ingress=INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER により LB 経由のみアクセス可能 (AWS の VPC Origin 相当)
# 公開トラフィックは LB → Cloud Run であり、Cloud Run に直接到達できないため allUsers Invoker は安全
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  project  = google_cloud_run_v2_service.backend.project
  location = google_cloud_run_v2_service.backend.location
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
