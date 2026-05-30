# GitHub Actions 用 OIDC (terraform plan / apply)
#
# 既存の Workload Identity Pool / Provider (workload_identity.tf) を使い、
# terraform plan (read) / apply (write) 専用のサービスアカウントを追加する。
#
# plan SA:  attribute.repository 条件 → PR や workflow_dispatch から利用可。
#           roles/viewer (プロジェクト全体の読み取り) + state バケット読み取り。
# apply SA: attribute.environment == "iac-apply" 条件 → GitHub Environment 承認後のみ利用可。
#           roles/owner (terraform が IAM リソースを作成するため) + state バケット読み書き。
#
# 登録が必要な GitHub Variables / Secrets は terraform output github_actions_terraform で確認。

# state バケットへの参照 (bootstrap/ で作成済み)
# plan/apply SA に IAM バインディングを付与するために使用する。
data "google_storage_bucket" "tfstate" {
  name = "${var.app-name}-${var.environment}-tfstate-${var.gcp-project-id}"
}

# ---------- plan 用 SA ----------

resource "google_service_account" "terraform_plan" {
  account_id   = "${var.app-name}-${var.environment}-tf-plan"
  display_name = "GitHub Actions Terraform Plan SA"
  description  = "Used by CI/CD for terraform plan (read-only)"
}

# plan SA は PR および workflow_dispatch (environment なし) から impersonate できる。
# attribute.repository で対象リポジトリを限定する。
resource "google_service_account_iam_member" "terraform_plan_wif" {
  service_account_id = google_service_account.terraform_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github-repository-name}"
}

# プロジェクト全体の読み取り (describe/list 系を網羅)
resource "google_project_iam_member" "terraform_plan_viewer" {
  project = var.gcp-project-id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.terraform_plan.email}"
}

# state バケットの読み取り
resource "google_storage_bucket_iam_member" "terraform_plan_state_reader" {
  bucket = data.google_storage_bucket.tfstate.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.terraform_plan.email}"
}

# ---------- apply 用 SA ----------

resource "google_service_account" "terraform_apply" {
  account_id   = "${var.app-name}-${var.environment}-tf-apply"
  display_name = "GitHub Actions Terraform Apply SA"
  description  = "Used by CI/CD for terraform apply (full access / iac-apply env only)"
}

# apply SA は GitHub Environment "iac-apply" が active なジョブのみ impersonate できる。
# Environment に必須レビュアーを設定することで apply 前に承認を必須化する。
resource "google_service_account_iam_member" "terraform_apply_wif" {
  service_account_id = google_service_account.terraform_apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.environment/iac-apply"
}

# terraform apply は SA / WIF / IAM 等を作成するため roles/owner が必要。
resource "google_project_iam_member" "terraform_apply_owner" {
  project = var.gcp-project-id
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.terraform_apply.email}"
}

# state バケットの読み書き
resource "google_storage_bucket_iam_member" "terraform_apply_state_admin" {
  bucket = data.google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_apply.email}"
}

# ---------- outputs ----------

output "github_actions_terraform" {
  description = "PR3 ワークフローに設定する GitHub Variables の値 (gh variable set で登録)"
  value = {
    TF_PLAN_SA_GCP  = google_service_account.terraform_plan.email
    TF_APPLY_SA_GCP = google_service_account.terraform_apply.email
    # WIF Provider は既存 output github_actions_secrets の GCP_WORKLOAD_IDENTITY_PROVIDER と同じ値
    TF_WIF_PROVIDER_GCP = "${google_iam_workload_identity_pool.github.name}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
  }
}
