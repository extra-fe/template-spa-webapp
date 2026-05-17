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
  description = "【環境変数で指定】GitHubリポジトリ名"
}
variable "codestar-connection-arn" {
  description = "【環境変数で指定】接続のarn"
}

## AWSアカウントIDとリージョンの変数(実行中のAWS環境から自動取得)
data "aws_caller_identity" "self" {}
data "aws_region" "current" {}

## アプリ名と環境(各リソース名のプレフィックスとして利用)
variable "app-name" {
  default = "sandbox-aws"
}

variable "environment" {
  default = "dev"
}

variable "frontend-src-root" {
  default     = "frontend/sandbox-frontend"
  description = "frontendのルートパス"
}

variable "target-branch" {
  default     = "main"
  description = "このブランチにPushされたときにCodePipelineをトリガー"
}

## S3のバケット名をユニークにするための乱数(グローバル一意制約への対応)
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  lower   = true
  numeric = true
  special = false
}

variable "backend-src-root" {
  default     = "backend/sandbox-backend"
  description = "backendのルートパス"
}

# VPCに割り当てるCIDRブロック
variable "vpc_cidr_block" {
  default = "172.16.0.0/16"
}
# パブリックサブネット(AZ-1a)のCIDR
variable "subnet_public1a_cidr_block" {
  default = "172.16.1.0/24"
}

# プライベートサブネット(AZ-1a)のCIDR
variable "subnet_private1a_cidr_block" {
  default = "172.16.2.0/24"
}

# プライベートサブネット(AZ-1c)のCIDR
variable "subnet_private1c_cidr_block" {
  default = "172.16.3.0/24"
}

variable "api-base-path" {
  default     = "/api/*"
  description = "backendのbase-path。このpathが増える場合は、CloudFrontのビヘイビアとALBリスナールールを追加する"
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

# Prismaコネクションプール設定
# 設定指針: ECSタスク最大数 × db-connection-limit ≦ Aurora最大コネクション数 × 0.8 (安全マージン)
# Aurora最大コネクション数の目安 (DBInstanceClassMemory / 9,531,392):
#   Serverless v2 1ACU    → 約   90
#   db.t3.medium  (4GiB)  → 約  450
#   db.m5.large   (8GiB)  → 約  900
#   db.m5.xlarge  (16GiB) → 約 1800
#   db.m5.2xlarge (32GiB) → 約 3600
variable "db-connection-limit" {
  type        = number
  default     = 5
  description = "Prismaが1プロセスで保持するコネクション数の上限。ECSタスク数との積がAuroraの最大コネクション数を超えないよう設定する"
}

# Prismaがコネクションプールの空きを待つタイムアウト(秒)
variable "db-pool-timeout" {
  type        = number
  default     = 15
  description = "Prismaのコネクションプール空き待ちタイムアウト(秒)"
}
