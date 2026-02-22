## 環境変数で指定する。terraform.tfvars に記載
variable "auth0_domain" {
  description = "【環境変数で指定】認証用アプリケーションのDomain"
}
variable "auth0_client_id" {
  description = "【環境変数で指定】認証用アプリケーションのClient ID"
}
variable "auth0_client_secret" {
  description = "【環境変数で指定】認証用アプリケーションのClient Secrets"
}

variable "gcp-project-id" {
  description = "【環境変数で指定】GCPプロジェクトID"
}

variable "github-repository-name" {
  description = "【環境変数で指定】GitHubリポジトリ名 (owner/repo 形式)"
}

## GCPプロジェクト情報
data "google_project" "current" {}

## アプリ名と環境
variable "app-name" {
  default = "sandbox-gcp"
}

variable "environment" {
  default = "dev"
}

variable "region" {
  type    = string
  default = "asia-northeast1"
}

variable "frontend-src-root" {
  default     = "frontend/sandbox-frontend"
  description = "frontendのルートパス"
}

variable "backend-src-root" {
  default     = "backend/sandbox-backend"
  description = "backendのルートパス"
}

variable "target-branch" {
  default     = "main"
  description = "このブランチにPushされたときにCloud Buildをトリガー"
}

## バケット名をユニークにするための乱数
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  lower   = true
  numeric = true
  special = false
}

variable "vpc-cidr-block" {
  default = "10.0.0.0/16"
}

variable "subnet-public-cidr-block" {
  default = "10.0.1.0/24"
}

variable "subnet-private-cidr-block" {
  default = "10.0.2.0/24"
}

variable "api-base-path" {
  default     = "/api/*"
  description = "backendのbase-path。このpathが増える場合は、URL Mapのルールを追加する"
}

variable "health-check-path" {
  default     = "/health"
  description = "backend側で作ったヘルスチェックのエンドポイント"
}

variable "api-expose-port" {
  type        = number
  default     = 3000
  description = "DockerfileでEXPOSEしているポートを指定"
}

variable "local-pc-ip-addresses" {
  type        = list(string)
  default     = []
  description = "接続元のIPアドレス"
}
