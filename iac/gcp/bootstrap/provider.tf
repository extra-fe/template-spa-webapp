# Terraform state backend ブートストラップ (GCP)
#
# リモート state backend (GCS バケット) 自体を作成するモジュール。
# 鶏卵問題を避けるためローカル state で実行する (backend ブロックを持たない)。
# 適用は初回 1 回のみ手動で行う (詳細は README.md を参照)。
provider "google" {
  project = var.gcp-project-id
  region  = var.gcp-region
}

terraform {
  required_version = ">= 1.13.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0"
    }
  }
}
