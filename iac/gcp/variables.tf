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

variable "github-repository-name" {
  description = "【環境変数で指定】GitHubリポジトリ名 (owner/repo 形式)"
}

variable "github-owner" {
  description = "GitHub Owner 名 (Workload Identity Federation の attribute_condition で使用)"
}

# GitHub Actions の Environment 名 (この Environment 名で実行された workflow のみが
# WIF 経由でデプロイ SA を impersonate できる)
variable "github-environment" {
  default     = "gcp-main"
  description = "GitHub Actions Environment 名 (Azure と区別するため gcp-main を既定)"
}

## GCPプロジェクトとリージョン
variable "gcp-project-id" {
  description = "【環境変数で指定】GCP プロジェクト ID"
}

variable "gcp-region" {
  default     = "asia-northeast1"
  description = "GCP リージョン (東京)"
}

variable "gcp-zone" {
  default     = "asia-northeast1-a"
  description = "GCP ゾーン (Bastion VM 配置先)"
}

## アプリ名と環境(各リソース名のプレフィックスとして利用)
variable "app-name" {
  default = "sandbox-gcp"
}

variable "environment" {
  default = "dev"
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

## Cloud Storage のバケット名をユニークにするための乱数(グローバル一意制約への対応)
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  lower   = true
  numeric = true
  special = false
}

# VPC に割り当てる主サブネット CIDR
variable "subnet_primary_cidr_block" {
  default     = "172.16.2.0/24"
  description = "Cloud Run コネクタ / Bastion / Cloud SQL 用プライマリサブネット"
}

# Serverless VPC Access コネクタ用サブネット (/28 必須)
variable "subnet_connector_cidr_block" {
  default     = "172.16.4.0/28"
  description = "Serverless VPC Access コネクタ専用 /28 サブネット"
}

# Cloud SQL Private Service Access 用予約レンジ
variable "psa_range_cidr_block" {
  default     = "172.16.16.0/20"
  description = "Cloud SQL / Memorystore 等の Private Service Access 用予約 IP レンジ (/16-/24)"
}

variable "api-base-path" {
  default     = "/api/*"
  description = "backendのbase-path。このpathが増える場合は、URL マップに追加する"
}

variable "health-check-path" {
  default     = "/health"
  description = "backend側で作ったヘルスチェックのエンドポイント"
}

variable "api-expose-port" {
  type        = number
  default     = 3000
  description = "DockerfileでEXPOSEしているポートを指定 (Cloud Run コンテナポート)"
}

variable "local-pc-ip-addresses" {
  type        = list(string)
  default     = []
  description = "接続元のIPアドレス (Bastion 用 IAP では不要だが、参考のため AWS と揃える)"
}

# Prismaコネクションプール設定 (AWS と同じ指針)
# 設定指針: Cloud Run 最大インスタンス数 × db-connection-limit ≦ Cloud SQL 最大コネクション数 × 0.8
# Cloud SQL の最大コネクションはマシンタイプで決まる (db-f1-micro: 25 / db-custom-1-3840: 100 / db-custom-2-7680: 200 etc.)
variable "db-connection-limit" {
  type        = number
  default     = 5
  description = "Prismaが1プロセスで保持するコネクション数の上限"
}

variable "db-pool-timeout" {
  type        = number
  default     = 15
  description = "Prismaのコネクションプール空き待ちタイムアウト(秒)"
}

# Cloud SQL のマシンタイプ (最小構成の例)
variable "db-tier" {
  default     = "db-custom-1-3840"
  description = "Cloud SQL マシンタイプ"
}

# 監視アラート通知先 (Pub/Sub topic のサブスクライブは Terraform 外で管理)
variable "alert-notification-emails" {
  type        = list(string)
  default     = []
  description = "Cloud Monitoring アラート通知先 email (空の場合は通知チャネル未作成)"
}

# 公開ドメイン (Managed SSL 証明書 + HTTPS リダイレクトに使用)
# 空文字の場合は HTTP のみで LB を構成 (PoC 用)
variable "lb-domain" {
  default     = ""
  description = "External Application LB の公開ドメイン名 (例: app.example.com)。設定すると Managed SSL 証明書を作成し HTTPS リダイレクトを有効化"
}

# Cloud Run / フロントから参照する公開 URL
# ドメイン未設定時は http://<LB-IP>、設定時は https://<lb-domain>
locals {
  public_url = var.lb-domain == "" ? "http://${google_compute_global_address.lb_ip.address}" : "https://${var.lb-domain}"
}
