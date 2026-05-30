# Terraform state 専用 GCS バケット
#
# 既存のログ用バケット等とは分離し、state 専用に作成する (Issue #138)。
# GCS backend はオブジェクトの世代管理によるロックを内蔵するため別途ロック資源は不要。
# 名前はプロジェクト ID を含めグローバル一意にする。
resource "google_storage_bucket" "tfstate" {
  name          = "${var.app-name}-${var.environment}-tfstate-${var.gcp-project-id}"
  location      = var.gcp-region
  storage_class = "STANDARD"

  # state はチームの共有資産。誤削除防止のため force_destroy は無効。
  force_destroy = false

  # 一様バケットレベルアクセス (ACL を使わず IAM で一元管理)
  uniform_bucket_level_access = true

  # 公開を全面禁止 (state には機密が含まれる)
  public_access_prevention = "enforced"

  # state 破損時のロールバック手段としてオブジェクト世代管理を有効化
  versioning {
    enabled = true
  }

  # 古い世代の肥大化を防ぐ (10 世代を超えた古い state を削除)
  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      type = "Delete"
    }
  }
}
