## Cloud Run v2 サービス (NestJS API)
resource "google_cloud_run_v2_service" "backend" {
  name     = "${var.app-name}-${var.environment}-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = google_service_account.cloud-run.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${data.google_project.current.project_id}/${google_artifact_registry_repository.backend.repository_id}/backend:latest"

      ports {
        container_port = var.api-expose-port
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      ## 環境変数
      env {
        name  = "PORT"
        value = tostring(var.api-expose-port)
      }

      env {
        name  = "LOG_LEVEL"
        value = "debug"
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

      ## Secret Manager から取得する環境変数
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database-url.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "AUTH0_DOMAIN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.auth0-domain.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "AUTH0_AUDIENCE"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.auth0-audience.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "CORS_ORIGIN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.cors-origin.secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = var.health-check-path
          port = var.api-expose-port
        }
        initial_delay_seconds = 5
        period_seconds        = 10
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = var.health-check-path
          port = var.api-expose-port
        }
        period_seconds    = 30
        failure_threshold = 3
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_version.database-url,
    google_secret_manager_secret_version.auth0-domain,
    google_secret_manager_secret_version.auth0-audience,
    google_secret_manager_secret_version.cors-origin,
  ]

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }
}
