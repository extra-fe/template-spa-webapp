# AWSプロバイダ: 東京リージョン(ap-northeast-1)を既定とする
provider "aws" {
  region = "ap-northeast-1"
}

# CloudFront標準ログ(v2 CloudWatch Logs Delivery)用のus-east-1プロバイダ
# CloudFrontはグローバルサービスで、APIエンドポイントが us-east-1 に固定されている。
# aws_cloudwatch_log_delivery_source/destination/delivery 三点セットは CloudFront と同じリージョン(us-east-1)に配置する必要がある。
# (配信先S3バケット自体は ap-northeast-1 のままで問題ない)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Auth0プロバイダ: テナント情報を環境変数(terraform.tfvars)から注入
provider "auth0" {
  domain        = var.auth0_domain
  client_id     = var.auth0_client_id
  client_secret = var.auth0_client_secret
}

# Terraform本体とプロバイダのバージョン固定
terraform {
  required_version = ">= 1.13.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.24.0"
    }
    auth0 = {
      source = "auth0/auth0"
      # 1.34.0以降は auth0_client の oidc_logout ブロックのスキーマ厳密化により
      # 既存テナントの設定が drift として削除対象になるため、当面 1.33.0 にpin。
      # provider更新は別途検証PRで実施すること。
      version = "1.33.0"
    }
  }
}
