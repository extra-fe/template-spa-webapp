## GCS バケット (SPA 静的ファイル用)
resource "google_storage_bucket" "frontend" {
  name                        = "${var.app-name}-${var.environment}-frontend-${random_string.suffix.result}"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["Content-Type"]
    max_age_seconds = 3600
  }
}

## バケットを公開アクセス可能にする (LB経由でのアクセス用)
resource "google_storage_bucket_iam_member" "frontend-public-read" {
  bucket = google_storage_bucket.frontend.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
