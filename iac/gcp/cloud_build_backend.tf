# バックエンド CI/CD: Cloud Build → Artifact Registry → Cloud Deploy → Cloud Run
# AWS の CodePipeline (Source/Build/Deploy) と機能パリティ:
#   - Cloud Build trigger : GitHub push 検知 + 変更パスフィルタ
#   - inline build steps  : docker build → Artifact Registry push (AWS CodeBuild 相当)
#   - Cloud Deploy        : Cloud Run 本番デプロイ (AWS の ECS Deploy ステージ相当)
#
# 前提:
#   - Cloud Build GitHub App / Cloud Build GitHub Connection を事前承認し、
#     var.cloudbuild-github-connection に Connection リソース名を指定すること
#   - リポジトリのバックエンド配下に skaffold.yaml と cloud-run-service.yaml (manifests) を配置
#     (Cloud Deploy の cloud-run ターゲットは skaffold.yaml + manifest が必須)

# Cloud Build SA (バックエンドビルド+デプロイ専用)
resource "google_service_account" "cloudbuild_backend" {
  account_id   = "${var.app-name}-${var.environment}-cb-backend"
  display_name = "Cloud Build SA for backend pipeline"
}

# 必要な IAM (Artifact Registry push / Cloud Deploy release / Cloud Run 更新 / Logging)
resource "google_project_iam_member" "cb_backend_ar_writer" {
  project = var.gcp-project-id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloudbuild_backend.email}"
}

resource "google_project_iam_member" "cb_backend_clouddeploy_releaser" {
  project = var.gcp-project-id
  role    = "roles/clouddeploy.releaser"
  member  = "serviceAccount:${google_service_account.cloudbuild_backend.email}"
}

resource "google_project_iam_member" "cb_backend_logwriter" {
  project = var.gcp-project-id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild_backend.email}"
}

# Cloud Build から Cloud Deploy 経由で Cloud Run を更新する際の SA 借用権限
resource "google_service_account_iam_member" "cb_backend_act_as_clouddeploy" {
  service_account_id = google_service_account.clouddeploy_runner.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cloudbuild_backend.email}"
}

# Cloud Deploy が実際に Cloud Run を更新する SA
# AWS の ECS Deploy で使う execute_ecs_task に該当する役割
resource "google_service_account" "clouddeploy_runner" {
  account_id   = "${var.app-name}-${var.environment}-deploy"
  display_name = "Cloud Deploy runner SA"
}

resource "google_project_iam_member" "clouddeploy_runner_run_admin" {
  project = var.gcp-project-id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.clouddeploy_runner.email}"
}

# Cloud Run の SA を借用して image を差し替えるため
resource "google_service_account_iam_member" "clouddeploy_runner_act_as_run" {
  service_account_id = google_service_account.cloud_run.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.clouddeploy_runner.email}"
}

# Cloud Deploy ターゲット: 本番 Cloud Run
resource "google_clouddeploy_target" "prod" {
  location = var.gcp-region
  name     = "${var.app-name}-${var.environment}-target"

  run {
    location = "projects/${var.gcp-project-id}/locations/${var.gcp-region}"
  }

  execution_configs {
    usages          = ["RENDER", "DEPLOY"]
    service_account = google_service_account.clouddeploy_runner.email
  }

  depends_on = [google_project_service.services]
}

# Cloud Deploy デリバリーパイプライン: 単一ステージ (本番) のローリングデプロイ
resource "google_clouddeploy_delivery_pipeline" "backend" {
  location = var.gcp-region
  name     = "${var.app-name}-${var.environment}-backend-pipeline"

  serial_pipeline {
    stages {
      target_id = google_clouddeploy_target.prod.name
      profiles  = []
    }
  }
}

# Cloud Build トリガー: main push + backend/** 変更で発火
# Build phase で docker build → AR push、その後 gcloud deploy releases create でデプロイ
resource "google_cloudbuild_trigger" "backend" {
  name            = "${var.app-name}-${var.environment}-backend"
  location        = var.gcp-region
  service_account = google_service_account.cloudbuild_backend.id
  included_files  = ["${var.backend-src-root}/**"]

  repository_event_config {
    repository = var.cloudbuild-github-connection == "" ? null : "${var.cloudbuild-github-connection}/repositories/${replace(var.github-repository-name, "/", "-")}"

    push {
      branch = "^${var.target-branch}$"
    }
  }

  build {
    timeout = "1200s"
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }

    # docker build
    step {
      id   = "build"
      name = "gcr.io/cloud-builders/docker"
      dir  = var.backend-src-root
      args = [
        "build",
        "-t", "${var.gcp-region}-docker.pkg.dev/${var.gcp-project-id}/${google_artifact_registry_repository.backend.repository_id}/backend:$SHORT_SHA",
        "-t", "${var.gcp-region}-docker.pkg.dev/${var.gcp-project-id}/${google_artifact_registry_repository.backend.repository_id}/backend:latest",
        "-f", "Dockerfile",
        ".",
      ]
    }

    # push (latest + short SHA)
    step {
      id   = "push-sha"
      name = "gcr.io/cloud-builders/docker"
      args = ["push", "${var.gcp-region}-docker.pkg.dev/${var.gcp-project-id}/${google_artifact_registry_repository.backend.repository_id}/backend:$SHORT_SHA"]
    }
    step {
      id   = "push-latest"
      name = "gcr.io/cloud-builders/docker"
      args = ["push", "${var.gcp-region}-docker.pkg.dev/${var.gcp-project-id}/${google_artifact_registry_repository.backend.repository_id}/backend:latest"]
    }

    # Cloud Deploy へリリース投入 (skaffold.yaml が backend src root にある前提)
    step {
      id         = "release"
      name       = "gcr.io/google.com/cloudsdktool/cloud-sdk:slim"
      entrypoint = "bash"
      dir        = var.backend-src-root
      args = [
        "-c",
        join(" ", [
          "gcloud deploy releases create rel-$SHORT_SHA",
          "--delivery-pipeline=${google_clouddeploy_delivery_pipeline.backend.name}",
          "--region=${var.gcp-region}",
          "--images=backend=${var.gcp-region}-docker.pkg.dev/${var.gcp-project-id}/${google_artifact_registry_repository.backend.repository_id}/backend:$SHORT_SHA",
        ]),
      ]
    }

    images = [
      "${var.gcp-region}-docker.pkg.dev/${var.gcp-project-id}/${google_artifact_registry_repository.backend.repository_id}/backend:$SHORT_SHA",
      "${var.gcp-region}-docker.pkg.dev/${var.gcp-project-id}/${google_artifact_registry_repository.backend.repository_id}/backend:latest",
    ]
  }

  depends_on = [
    google_project_iam_member.cb_backend_ar_writer,
    google_project_iam_member.cb_backend_clouddeploy_releaser,
  ]
}
