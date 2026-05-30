variable "gcp-project-id" {
  description = "【環境変数で指定】GCP プロジェクト ID"
}

variable "gcp-region" {
  default     = "asia-northeast1"
  description = "state バケットを作成するリージョン (親 iac/gcp と揃える)"
}

variable "app-name" {
  default     = "sandbox-gcp"
  description = "リソース名プレフィックス (親 iac/gcp と揃える)"
}

variable "environment" {
  default     = "dev"
  description = "環境名 (親 iac/gcp と揃える)"
}
