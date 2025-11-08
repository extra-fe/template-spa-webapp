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

## AzureのサブスクリプションIDとリージョンの変数
variable "azure-subscription-id" {}
variable "location" {
  type    = string
  default = "japaneast"
}

## アプリ名と環境
variable "app-name" {
  default = "sandbox"
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
  description = "このブランチに対しての権限"
}


## ストレージアカウント名をユニークにするための乱数
data "azurerm_client_config" "current" {}
resource "random_string" "random" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

variable "backend-src-root" {
  default     = "backend/sandbox-backend"
  description = "backendのルートパス"
}
variable "api-base-path" {
  default     = "/api/*"
  description = "backendのbase-path。このpathが増える場合は、FrontDoorのrouteを追加する"
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

variable "public-key-vault-name" {
  default = ""
}

variable "public-key-vault-rg-name" {
  default = ""
}

variable "public-key-vault-secret" {
  default = ""
}
