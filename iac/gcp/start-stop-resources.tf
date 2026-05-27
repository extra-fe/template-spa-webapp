# 自動起動・停止: AWS の EventBridge Scheduler + Step Functions 相当
# - Cloud Scheduler: cron トリガー (Asia/Tokyo)
# - Cloud Workflows: 複数 GCP API を順次/並列で実行
#
# Auto-stop  : 毎日 21:00 JST (デフォルト有効)
#   1. Cloud Run min/max インスタンスを 0 にする (= 実質停止)
#   2. Cloud SQL インスタンスを停止
#   3. Bastion VM を停止
#
# Auto-start : 土日 7:00 JST (デフォルト無効 = paused)
#   1. Bastion VM を起動
#   2. Cloud SQL インスタンスを起動 → 起動完了まで待機
#   3. Cloud Run min/max インスタンスを 1 に戻す

# Workflows 実行用 SA
resource "google_service_account" "workflows" {
  account_id   = "${var.app-name}-${var.environment}-workflows"
  display_name = "Workflows SA for auto start/stop"
}

# Workflows SA に必要な権限を付与
# - Cloud SQL Admin: インスタンス起動/停止
# - Compute Instance Admin (v1): Bastion VM 起動/停止
# - Cloud Run Admin: Cloud Run サービスの scaling 更新
resource "google_project_iam_member" "workflows_sql_admin" {
  project = var.gcp-project-id
  role    = "roles/cloudsql.admin"
  member  = "serviceAccount:${google_service_account.workflows.email}"
}

resource "google_project_iam_member" "workflows_compute_admin" {
  project = var.gcp-project-id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.workflows.email}"
}

resource "google_project_iam_member" "workflows_run_admin" {
  project = var.gcp-project-id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.workflows.email}"
}

# Workflows 自身が他の SA (cloud_run SA) をなくしては Cloud Run 更新できない場合があるため
# Service Account User も付与
resource "google_project_iam_member" "workflows_sa_user" {
  project = var.gcp-project-id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.workflows.email}"
}

# Auto-stop ワークフロー
resource "google_workflows_workflow" "auto_stop" {
  name            = "${var.app-name}-${var.environment}-auto-stop"
  region          = var.gcp-region
  service_account = google_service_account.workflows.id

  source_contents = <<-EOT
    main:
      steps:
        - scale_run_to_zero:
            call: http.patch
            args:
              url: $${"https://run.googleapis.com/v2/projects/${var.gcp-project-id}/locations/${var.gcp-region}/services/${google_cloud_run_v2_service.backend.name}?updateMask=template.scaling"}
              auth:
                type: OAuth2
              body:
                template:
                  scaling:
                    minInstanceCount: 0
                    maxInstanceCount: 0
        - stop_sql:
            call: http.patch
            args:
              url: $${"https://sqladmin.googleapis.com/v1/projects/${var.gcp-project-id}/instances/${google_sql_database_instance.main.name}"}
              auth:
                type: OAuth2
              body:
                settings:
                  activationPolicy: NEVER
        - stop_bastion:
            call: googleapis.compute.v1.instances.stop
            args:
              project: ${var.gcp-project-id}
              zone: ${var.gcp-zone}
              instance: ${google_compute_instance.bastion.name}
        - done:
            return: "auto-stop completed"
  EOT

  depends_on = [google_project_service.services]
}

# Auto-start ワークフロー
resource "google_workflows_workflow" "auto_start" {
  name            = "${var.app-name}-${var.environment}-auto-start"
  region          = var.gcp-region
  service_account = google_service_account.workflows.id

  source_contents = <<-EOT
    main:
      steps:
        - start_bastion:
            call: googleapis.compute.v1.instances.start
            args:
              project: ${var.gcp-project-id}
              zone: ${var.gcp-zone}
              instance: ${google_compute_instance.bastion.name}
        - start_sql:
            call: http.patch
            args:
              url: $${"https://sqladmin.googleapis.com/v1/projects/${var.gcp-project-id}/instances/${google_sql_database_instance.main.name}"}
              auth:
                type: OAuth2
              body:
                settings:
                  activationPolicy: ALWAYS
        - wait_for_sql:
            call: sys.sleep
            args:
              seconds: 720
        - scale_run_back:
            call: http.patch
            args:
              url: $${"https://run.googleapis.com/v2/projects/${var.gcp-project-id}/locations/${var.gcp-region}/services/${google_cloud_run_v2_service.backend.name}?updateMask=template.scaling"}
              auth:
                type: OAuth2
              body:
                template:
                  scaling:
                    minInstanceCount: 0
                    maxInstanceCount: 10
        - done:
            return: "auto-start completed"
  EOT
}

# Cloud Scheduler 用 SA (Workflows を起動できる)
resource "google_service_account" "scheduler" {
  account_id   = "${var.app-name}-${var.environment}-scheduler"
  display_name = "Cloud Scheduler SA for workflow trigger"
}

resource "google_project_iam_member" "scheduler_workflow_invoker" {
  project = var.gcp-project-id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.scheduler.email}"
}

# Auto-stop スケジューラ: 毎日 21:00 JST = UTC 12:00
resource "google_cloud_scheduler_job" "auto_stop" {
  name      = "${var.app-name}-${var.environment}-auto-stop"
  region    = var.gcp-region
  schedule  = "0 21 * * *"
  time_zone = "Asia/Tokyo"

  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/${google_workflows_workflow.auto_stop.id}/executions"
    body        = base64encode("{}")

    oauth_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  depends_on = [google_project_iam_member.scheduler_workflow_invoker]
}

# Auto-start スケジューラ: 土日 7:00 JST、デフォルトは paused (= AWS の DISABLED 相当)
resource "google_cloud_scheduler_job" "auto_start" {
  name      = "${var.app-name}-${var.environment}-auto-start"
  region    = var.gcp-region
  schedule  = "0 7 * * 6,0"
  time_zone = "Asia/Tokyo"
  paused    = true

  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/${google_workflows_workflow.auto_start.id}/executions"
    body        = base64encode("{}")

    oauth_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  depends_on = [google_project_iam_member.scheduler_workflow_invoker]
}
