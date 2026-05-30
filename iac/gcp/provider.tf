# Google Cloud プロバイダ: 東京リージョン(asia-northeast1)を既定とする
# プロジェクト/リージョンは terraform.tfvars で指定
provider "google" {
  project = var.gcp-project-id
  region  = var.gcp-region
}

# google-beta プロバイダ: Cloud Run の一部機能 / Cloud Armor の adaptive protection 等で必要
provider "google-beta" {
  project = var.gcp-project-id
  region  = var.gcp-region
}

# Auth0プロバイダ: テナント情報を環境変数(terraform.tfvars)から注入
provider "auth0" {
  domain        = var.auth0_domain
  client_id     = var.auth0_client_id
  client_secret = var.auth0_client_secret
}

# Terraform本体とプロバイダのバージョン固定 (AWS/Azure 側と整合)
terraform {
  required_version = ">= 1.13.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.0.0"
    }
    auth0 = {
      source  = "auth0/auth0"
      version = "1.33.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.10.0"
    }
  }
}
