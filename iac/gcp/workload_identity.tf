# GitHub Actions 用 Workload Identity Federation (OIDC)
# AWS の CodeStar Connection / Azure の Federated Identity Credential 相当。
# 静的サービスアカウントキーを使わず、GitHub の OIDC トークンを直接 GCP に持ち込んで
# サービスアカウントを impersonation する方式。
#
# 使い方:
#   1. terraform apply 後、outputs (terraform output github_actions_variables_json /
#      github_actions_secrets) で GitHub Environments に登録する値を取得
#   2. GitHub の Repository → Settings → Environments → "main" Environment を作成
#   3. 上記 outputs の値を Variables / Secrets に登録
#   4. GitHub Actions の workflow_dispatch から手動デプロイ

# Workload Identity Pool: GitHub OIDC トークンの受け入れ先
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "${var.app-name}-${var.environment}-gh"
  display_name              = "GitHub Actions"
  description               = "Workload Identity Pool for GitHub Actions OIDC"
  disabled                  = false

  depends_on = [google_project_service.services]
}

# Workload Identity Provider: GitHub の OIDC トークンを検証
# attribute_condition で対象リポジトリを限定 (他リポジトリからの impersonation を防ぐ)
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
    "attribute.actor"            = "assertion.actor"
    "attribute.environment"      = "assertion.environment"
  }

  attribute_condition = "assertion.repository == \"${var.github-repository-name}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ---------- バックエンドデプロイ用 SA ----------
resource "google_service_account" "github_actions_backend" {
  account_id   = "${var.app-name}-${var.environment}-ga-be"
  display_name = "GitHub Actions Backend Deploy SA"
}

# GitHub Actions が OIDC 経由でこの SA を impersonate するための binding
resource "google_service_account_iam_member" "github_actions_backend_wif" {
  service_account_id = google_service_account.github_actions_backend.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.environment/${var.github-environment}"
}

# Artifact Registry へ push する権限
resource "google_artifact_registry_repository_iam_member" "github_actions_backend_writer" {
  location   = google_artifact_registry_repository.backend.location
  repository = google_artifact_registry_repository.backend.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.github_actions_backend.email}"
}

# Cloud Run サービス更新権限
resource "google_cloud_run_v2_service_iam_member" "github_actions_backend_admin" {
  project  = google_cloud_run_v2_service.backend.project
  location = google_cloud_run_v2_service.backend.location
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.admin"
  member   = "serviceAccount:${google_service_account.github_actions_backend.email}"
}

# Cloud Run サービス更新時、ランタイム SA を借用するために必要
resource "google_service_account_iam_member" "github_actions_backend_act_as_run" {
  service_account_id = google_service_account.cloud_run.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_actions_backend.email}"
}

# ---------- フロントエンドデプロイ用 SA ----------
resource "google_service_account" "github_actions_frontend" {
  account_id   = "${var.app-name}-${var.environment}-ga-fe"
  display_name = "GitHub Actions Frontend Deploy SA"
}

resource "google_service_account_iam_member" "github_actions_frontend_wif" {
  service_account_id = google_service_account.github_actions_frontend.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.environment/${var.github-environment}"
}

# GCS バケットへの書き込み権限
resource "google_storage_bucket_iam_member" "github_actions_frontend_writer" {
  bucket = google_storage_bucket.web.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.github_actions_frontend.email}"
}

# Cloud CDN キャッシュ無効化権限
# URL マップに対する compute.urlMaps.invalidateCache を含む
resource "google_project_iam_member" "github_actions_frontend_cdn_invalidator" {
  project = var.gcp-project-id
  role    = "roles/compute.loadBalancerAdmin"
  member  = "serviceAccount:${google_service_account.github_actions_frontend.email}"
}
