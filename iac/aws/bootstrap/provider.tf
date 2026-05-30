# Terraform state backend ブートストラップ (AWS)
#
# このモジュールは「リモート state backend 自体を作成する」ためのものなので、
# 鶏卵問題を避けるためにローカル state で実行する (backend ブロックを持たない)。
# ここで作った S3 バケットを、親 (iac/aws) の backend "s3" が利用する。
#
# 適用は初回 1 回のみ手動で行う (詳細は README.md を参照)。
provider "aws" {
  region = var.aws-region
}

terraform {
  required_version = ">= 1.13.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.24.0"
    }
  }
}
