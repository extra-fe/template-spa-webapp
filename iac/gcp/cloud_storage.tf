# 静的Webアセット配信用 Cloud Storage バケット (LB Backend Bucket 経由でのみ公開)
# AWS の S3 バケット (web) 相当
resource "google_storage_bucket" "web" {
  name                        = "${var.app-name}-${var.environment}-web-${random_string.suffix.result}"
  location                    = var.gcp-region
  storage_class               = "STANDARD"
  force_destroy               = true
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # SPA ルーティング: 存在しないパスは index.html を返す
  # AWS CloudFront の custom_error_response (403 → /index.html) と同等の挙動を実現
  # Cloud CDN 経由でも notFoundPage が機能する
  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }

  # CORS は CloudFront 経由で API を叩く構成のため通常不要だが、
  # フロントから直接 GCS にアクセスするケースに備えて空配列で明示
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  versioning {
    enabled = false
  }
}

# Cloud CDN の LB がバケットを読むためのサービスアカウントに objectViewer を付与
# (Backend Bucket は IAM 経由で参照するため、バケット ACL は不要)
# 注: GCS Backend Bucket は自動的に Cloud CDN サービスアカウントからアクセスされる。
# バケットが uniform_bucket_level_access の場合、明示的に Storage Object Viewer を付与する。
resource "google_storage_bucket_iam_member" "web_cdn_viewer" {
  bucket = google_storage_bucket.web.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:service-${data.google_project.self.number}@cloud-cdn-fill.iam.gserviceaccount.com"
}
