# GitHub Actions が参照する値を Terraform output として公開
# Azure 側の outputs.tf と同じ思想:
#   - github_actions_variables_json: 非秘密 (GitHub Environments > Variables 登録)
#   - github_actions_secrets       : 秘密 (GitHub Environments > Secrets 登録)
#
# 取得例:
#   terraform output -raw github_actions_variables_json
#   terraform output -json github_actions_secrets

output "lb_ip" {
  description = "External LB の公開 IP"
  value       = google_compute_global_address.lb_ip.address
}

output "cloud_run_service_name" {
  description = "Cloud Run サービス名"
  value       = google_cloud_run_v2_service.backend.name
}

output "artifact_registry_repository" {
  description = "Artifact Registry リポジトリ名 (backend イメージ用)"
  value       = google_artifact_registry_repository.backend.repository_id
}

output "frontend_bucket_name" {
  description = "フロントエンド配信用 GCS バケット名"
  value       = google_storage_bucket.web.name
}

output "url_map_name" {
  description = "LB URL マップ名 (Cloud CDN invalidation で利用)"
  value       = google_compute_url_map.main.name
}

# GitHub Actions Environments > Variables 用 (非秘密)
output "github_actions_variables_json" {
  description = "GitHub Environments > Variables に登録する値 (JSON)"
  value = jsonencode({
    GCP_PROJECT_ID                = var.gcp-project-id
    GCP_REGION                    = var.gcp-region
    GCP_ARTIFACT_REGISTRY_REPO    = google_artifact_registry_repository.backend.repository_id
    GCP_BACKEND_IMAGE_NAME        = "backend"
    GCP_BACKEND_SERVICE_NAME      = google_cloud_run_v2_service.backend.name
    GCP_FRONTEND_BUCKET           = google_storage_bucket.web.name
    GCP_URL_MAP_NAME              = google_compute_url_map.main.name
    GCP_BACKEND_WORKING_DIRECTORY = "/${var.backend-src-root}"
    GCP_FRONTEND_WORKING_DIRECTORY = "/${var.frontend-src-root}"
    VITE_API_BASE_URL             = local.public_url
  })
}

# GitHub Actions Environments > Secrets 用 (秘密)
output "github_actions_secrets" {
  description = "GitHub Environments > Secrets に登録する値"
  sensitive   = true
  value = {
    GCP_WORKLOAD_IDENTITY_PROVIDER  = "${google_iam_workload_identity_pool.github.name}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
    GCP_BACKEND_SERVICE_ACCOUNT     = google_service_account.github_actions_backend.email
    GCP_FRONTEND_SERVICE_ACCOUNT    = google_service_account.github_actions_frontend.email
    VITE_AUTH0_DOMAIN               = var.auth0_domain
    VITE_AUTH0_CLIENT_ID            = auth0_client.app.client_id
    VITE_AUTH0_AUDIENCE             = local.public_url
  }
}
