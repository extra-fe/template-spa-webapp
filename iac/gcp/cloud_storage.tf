# 静的Webアセット配信用 Cloud Storage バケット (Cloud CDN 経由で配信)
# AWS の S3 バケット (web) 相当
#
# 注: Backend Bucket + Cloud CDN で公開する場合の標準パターンとして
# allUsers に objectViewer を付与し、public_access_prevention を inherited にする。
# cloud-cdn-fill サービスエージェント (オンデマンド作成) を待つ方式は初回 apply で
# 競合しやすいため、本テンプレートでは公開バケットパターンを採用。
# (LB 経由でも直接 storage.googleapis.com 経由でも同じ静的アセットが配信されるだけで
#  実質的な情報漏洩リスクはない)
resource "google_storage_bucket" "web" {
  name                        = "${var.app-name}-${var.environment}-web-${random_string.suffix.result}"
  location                    = var.gcp-region
  storage_class               = "STANDARD"
  force_destroy               = true
  uniform_bucket_level_access = true
  public_access_prevention    = "inherited"

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

# allUsers に objectViewer を付与してバケット内容を公開読みにする
# (Cloud CDN backend bucket + 静的アセット配信の標準パターン)
resource "google_storage_bucket_iam_member" "web_public_viewer" {
  bucket = google_storage_bucket.web.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
