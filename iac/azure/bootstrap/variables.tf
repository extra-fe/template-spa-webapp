variable "azure-subscription-id" {
  description = "【環境変数で指定】Azure サブスクリプション ID"
}

variable "location" {
  type        = string
  default     = "japaneast"
  description = "state ストレージを作成するリージョン (親 iac/azure と揃える)"
}

variable "app-name" {
  default     = "sandbox"
  description = "リソース名プレフィックス (親 iac/azure と揃える)"
}

variable "environment" {
  default     = "dev"
  description = "環境名 (親 iac/azure と揃える)"
}

# Storage Account 名 (3-24 文字・英数小文字) のグローバル一意化用サフィックス
resource "random_string" "random" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}
