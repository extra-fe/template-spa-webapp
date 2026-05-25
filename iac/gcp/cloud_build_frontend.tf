# フロントエンド CI/CD: Cloud Build → GCS sync → Cloud CDN invalidation
# AWS の CodePipeline frontend (Source/Build → S3 sync + CloudFront invalidation) と同等
#
# 前提:
#   - Cloud Build GitHub Connection を事前承認 (バックエンド側と共有)
#   - skaffold は不要 (静的アセットのため Cloud Deploy は使わない)

# Cloud Build SA (フロントエンドデプロイ専用)
resource "google_service_account" "cloudbuild_frontend" {
  account_id   = "${var.app-name}-${var.environment}-cb-front"
  display_name = "Cloud Build SA for frontend pipeline"
}

# GCS バケットへの書き込み権限
resource "google_storage_bucket_iam_member" "cb_frontend_writer" {
  bucket = google_storage_bucket.web.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cloudbuild_frontend.email}"
}

# Cloud CDN キャッシュ無効化権限
resource "google_project_iam_member" "cb_frontend_cdn_invalidator" {
  project = var.gcp-project-id
  role    = "roles/compute.loadBalancerAdmin"
  member  = "serviceAccount:${google_service_account.cloudbuild_frontend.email}"
}

resource "google_project_iam_member" "cb_frontend_logwriter" {
  project = var.gcp-project-id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild_frontend.email}"
}

# Cloud Build トリガー: main push + frontend/** 変更で発火
# Cloud Build GitHub Connection が未設定の場合はトリガー自体を作成しない
resource "google_cloudbuild_trigger" "frontend" {
  count           = var.cloudbuild-github-connection == "" ? 0 : 1
  name            = "${var.app-name}-${var.environment}-frontend"
  location        = var.gcp-region
  service_account = google_service_account.cloudbuild_frontend.id
  included_files  = ["${var.frontend-src-root}/**"]

  repository_event_config {
    repository = "${var.cloudbuild-github-connection}/repositories/${replace(var.github-repository-name, "/", "-")}"

    push {
      branch = "^${var.target-branch}$"
    }
  }

  build {
    timeout = "900s"
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }

    # Node 22 + yarn セットアップ → ビルド
    step {
      id         = "install-build"
      name       = "node:22-slim"
      entrypoint = "bash"
      dir        = var.frontend-src-root
      args = [
        "-c",
        join(" && ", [
          "corepack enable",
          "yarn --version",
          "cat > .env <<EOF\nVITE_AUTH0_DOMAIN=${var.auth0_domain}\nVITE_AUTH0_CLIENT_ID=${auth0_client.app.client_id}\nVITE_AUTH0_AUDIENCE=${local.public_url}\nVITE_API_BASE_URL=${local.public_url}\nEOF",
          "yarn install --frozen-lockfile",
          "yarn build",
        ]),
      ]
    }

    # GCS sync (index.html を除く)
    step {
      id         = "sync-assets"
      name       = "gcr.io/google.com/cloudsdktool/cloud-sdk:slim"
      entrypoint = "bash"
      dir        = var.frontend-src-root
      args = [
        "-c",
        "gcloud storage rsync ./dist gs://${google_storage_bucket.web.name}/ --recursive --delete-unmatched-destination-objects --exclude='index.html'",
      ]
    }

    # index.html を Cache-Control no-store, no-cache 付きでアップロード
    step {
      id         = "upload-index"
      name       = "gcr.io/google.com/cloudsdktool/cloud-sdk:slim"
      entrypoint = "bash"
      dir        = var.frontend-src-root
      args = [
        "-c",
        "gcloud storage cp ./dist/index.html gs://${google_storage_bucket.web.name}/index.html --cache-control='no-store, no-cache'",
      ]
    }

    # Cloud CDN キャッシュ無効化 (/* 全パス)
    step {
      id         = "invalidate"
      name       = "gcr.io/google.com/cloudsdktool/cloud-sdk:slim"
      entrypoint = "bash"
      args = [
        "-c",
        join(" ", [
          "gcloud compute url-maps invalidate-cdn-cache ${google_compute_url_map.main.name}",
          "--path '/*'",
          "--global",
          "--async",
        ]),
      ]
    }
  }

  depends_on = [
    google_storage_bucket_iam_member.cb_frontend_writer,
    google_project_iam_member.cb_frontend_cdn_invalidator,
  ]
}
