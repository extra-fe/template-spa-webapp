# Secret Manager: AWS の SSM Parameter Store (SecureString) 相当
# DATABASE_URL を格納し、Cloud Run の env から参照する。
resource "google_secret_manager_secret" "db_connection_string" {
  secret_id = "${var.app-name}-${var.environment}-database-url"

  replication {
    user_managed {
      replicas {
        location = var.gcp-region
      }
    }
  }

  depends_on = [google_project_service.services]
}

resource "google_secret_manager_secret_version" "db_connection_string" {
  secret      = google_secret_manager_secret.db_connection_string.id
  secret_data = local.database_url
}
