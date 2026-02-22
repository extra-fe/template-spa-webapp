## Artifact Registry (Docker リポジトリ)
resource "google_artifact_registry_repository" "backend" {
  location      = var.region
  repository_id = "${var.app-name}-${var.environment}-backend"
  format        = "DOCKER"
  description   = "Docker repository for ${var.app-name}-${var.environment} backend"

  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"

    most_recent_versions {
      keep_count = 10
    }
  }
}
