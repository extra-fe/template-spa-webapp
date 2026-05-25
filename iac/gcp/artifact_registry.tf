# Artifact Registry: AWS の ECR 相当
# バックエンド Docker イメージを保管 (Cloud Run が pull する)
resource "google_artifact_registry_repository" "backend" {
  location      = var.gcp-region
  repository_id = "${var.environment}-${var.app-name}-backend"
  format        = "DOCKER"
  description   = "Backend container images for ${var.app-name}-${var.environment}"

  # 脆弱性スキャンは Artifact Analysis (旧 Container Analysis) で別途有効化
  # ProjectService で containeranalysis.googleapis.com を追加することで自動スキャン
  depends_on = [google_project_service.services]
}
