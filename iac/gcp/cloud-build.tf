## Cloud Build トリガー: バックエンド
## backend-src-root 配下の変更で Docker build → Artifact Registry push → Cloud Run デプロイ
resource "google_cloudbuild_trigger" "backend" {
  name        = "${var.app-name}-${var.environment}-backend"
  description = "Backend: Docker build → AR push → Cloud Run deploy"

  github {
    owner = split("/", var.github-repository-name)[0]
    name  = split("/", var.github-repository-name)[1]

    push {
      branch = "^${var.target-branch}$"
    }
  }

  included_files = ["${var.backend-src-root}/**"]

  service_account = google_service_account.cloud-build.id

  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "${var.region}-docker.pkg.dev/${data.google_project.current.project_id}/${google_artifact_registry_repository.backend.repository_id}/backend:$COMMIT_SHA",
        "-t", "${var.region}-docker.pkg.dev/${data.google_project.current.project_id}/${google_artifact_registry_repository.backend.repository_id}/backend:latest",
        "-f", "./${var.backend-src-root}/Dockerfile",
        "./${var.backend-src-root}",
      ]
    }

    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "--all-tags",
        "${var.region}-docker.pkg.dev/${data.google_project.current.project_id}/${google_artifact_registry_repository.backend.repository_id}/backend",
      ]
    }

    step {
      name       = "gcr.io/google.com/cloudsdktool/cloud-sdk"
      entrypoint = "gcloud"
      args = [
        "run",
        "services",
        "update",
        google_cloud_run_v2_service.backend.name,
        "--region", var.region,
        "--image", "${var.region}-docker.pkg.dev/${data.google_project.current.project_id}/${google_artifact_registry_repository.backend.repository_id}/backend:$COMMIT_SHA",
      ]
    }

    options {
      logging = "CLOUD_LOGGING_ONLY"
    }

    timeout = "1200s"
  }
}

## Cloud Build トリガー: フロントエンド
## frontend-src-root 配下の変更で yarn build → GCS upload → CDN キャッシュ無効化
resource "google_cloudbuild_trigger" "frontend" {
  name        = "${var.app-name}-${var.environment}-frontend"
  description = "Frontend: yarn build → GCS upload → CDN cache invalidation"

  github {
    owner = split("/", var.github-repository-name)[0]
    name  = split("/", var.github-repository-name)[1]

    push {
      branch = "^${var.target-branch}$"
    }
  }

  included_files = ["${var.frontend-src-root}/**"]

  service_account = google_service_account.cloud-build.id

  build {
    step {
      name       = "node:23"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          npm install -g yarn && \
          cd ./${var.frontend-src-root} && \
          touch .env && \
          echo "VITE_AUTH0_DOMAIN=${var.auth0_domain}" > .env && \
          echo "VITE_AUTH0_CLIENT_ID=${auth0_client.app.client_id}" >> .env && \
          echo "VITE_AUTH0_AUDIENCE=http://${google_compute_global_address.lb-ip.address}" >> .env && \
          echo "VITE_API_BASE_URL=http://${google_compute_global_address.lb-ip.address}" >> .env && \
          yarn install && \
          yarn build
        EOT
      ]
    }

    step {
      name       = "gcr.io/google.com/cloudsdktool/cloud-sdk"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          gsutil -m rsync -r -d ./${var.frontend-src-root}/dist gs://${google_storage_bucket.frontend.name}/ && \
          gcloud compute url-maps invalidate-cdn-cache ${google_compute_url_map.default.name} --path "/*" --global
        EOT
      ]
    }

    options {
      logging = "CLOUD_LOGGING_ONLY"
    }

    timeout = "1200s"
  }
}
