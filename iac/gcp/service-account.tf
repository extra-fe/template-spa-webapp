## Cloud Run 用サービスアカウント
resource "google_service_account" "cloud-run" {
  account_id   = "${var.app-name}-${var.environment}-run-sa"
  display_name = "Cloud Run Service Account for ${var.app-name}-${var.environment}"
}

## Cloud Run SA に Secret Manager のアクセス権限を付与
resource "google_project_iam_member" "cloud-run-secret-accessor" {
  project = data.google_project.current.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloud-run.email}"
}

## Cloud Run SA に Cloud SQL クライアント権限を付与
resource "google_project_iam_member" "cloud-run-cloudsql-client" {
  project = data.google_project.current.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloud-run.email}"
}

## Cloud Run SA に Cloud Logging 書き込み権限を付与
resource "google_project_iam_member" "cloud-run-log-writer" {
  project = data.google_project.current.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud-run.email}"
}

## Cloud Build 用サービスアカウント
resource "google_service_account" "cloud-build" {
  account_id   = "${var.app-name}-${var.environment}-build-sa"
  display_name = "Cloud Build Service Account for ${var.app-name}-${var.environment}"
}

## Cloud Build SA に Artifact Registry 書き込み権限を付与
resource "google_project_iam_member" "cloud-build-ar-writer" {
  project = data.google_project.current.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloud-build.email}"
}

## Cloud Build SA に Cloud Run デプロイ権限を付与
resource "google_project_iam_member" "cloud-build-run-developer" {
  project = data.google_project.current.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.cloud-build.email}"
}

## Cloud Build SA が Cloud Run SA を使用できるようにする
resource "google_service_account_iam_member" "cloud-build-act-as-run" {
  service_account_id = google_service_account.cloud-run.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cloud-build.email}"
}

## Cloud Build SA に Cloud Storage 管理権限を付与 (フロントエンドデプロイ用)
resource "google_project_iam_member" "cloud-build-storage-admin" {
  project = data.google_project.current.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.cloud-build.email}"
}

## Cloud Build SA に Cloud CDN キャッシュ無効化権限を付与
resource "google_project_iam_member" "cloud-build-compute-lb-admin" {
  project = data.google_project.current.project_id
  role    = "roles/compute.loadBalancerAdmin"
  member  = "serviceAccount:${google_service_account.cloud-build.email}"
}

## Cloud Build SA にログ書き込み権限を付与
resource "google_project_iam_member" "cloud-build-log-writer" {
  project = data.google_project.current.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud-build.email}"
}

## Cloud Build SA に Secret Manager アクセス権限を付与 (ビルド時の環境変数参照用)
resource "google_project_iam_member" "cloud-build-secret-accessor" {
  project = data.google_project.current.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloud-build.email}"
}

## Bastion 用サービスアカウント
resource "google_service_account" "bastion" {
  account_id   = "${var.app-name}-${var.environment}-bst-sa"
  display_name = "Bastion Service Account for ${var.app-name}-${var.environment}"
}

## Bastion SA に IAP Tunnel 利用権限を付与
resource "google_project_iam_member" "bastion-iap-tunnel" {
  project = data.google_project.current.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${google_service_account.bastion.email}"
}

## Bastion SA に Cloud SQL クライアント権限を付与
resource "google_project_iam_member" "bastion-cloudsql-client" {
  project = data.google_project.current.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.bastion.email}"
}
