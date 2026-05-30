# Terraform state backend ブートストラップ (Azure)
#
# リモート state backend (Storage Account + コンテナ) 自体を作成するモジュール。
# 鶏卵問題を避けるためローカル state で実行する (backend ブロックを持たない)。
# 適用は初回 1 回のみ手動で行う (詳細は README.md を参照)。
provider "azurerm" {
  subscription_id = var.azure-subscription-id
  features {}
}

terraform {
  required_version = ">= 1.13.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.30.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.0"
    }
  }
}
