variable "aws-region" {
  default     = "ap-northeast-1"
  description = "state バケットを作成するリージョン (親 iac/aws と揃える)"
}

variable "app-name" {
  default     = "sandbox-aws"
  description = "リソース名プレフィックス (親 iac/aws と揃える)"
}

variable "environment" {
  default     = "dev"
  description = "環境名 (親 iac/aws と揃える)"
}

# 実行中の AWS アカウント ID (state バケット名のグローバル一意化に利用)
data "aws_caller_identity" "self" {}
