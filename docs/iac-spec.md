# IaC (Infrastructure as Code) 仕様書

## 1. 概要

AWS と Azure の両クラウドに同一アプリケーションをデプロイするためのインフラ定義。Terraformで全リソースを管理し、CI/CDパイプラインによる自動デプロイを実現する。

| 項目 | 値 |
|---|---|
| IaCツール | Terraform 1.13.5 |
| 対象クラウド | AWS, Azure |
| 認証基盤 | Auth0（両クラウド共通） |
| ソースパス | `iac/aws/`, `iac/azure/` |

## 2. アーキテクチャ概要

### 共通設計方針

| 方針 | 説明 |
|---|---|
| CDN-First | 全トラフィックをCDN (CloudFront / Front Door) 経由で処理 |
| サーバーレス/PaaS優先 | Fargate, Aurora Serverless, App Service等を採用（EC2/VM不使用） |
| コンテナベースバックエンド | Docker イメージでバックエンドを統一 |
| プライベートDB | データベースはVPC/VNet内に配置、パブリックアクセス不可 |
| シークレット管理 | SSM Parameter Store (AWS) / Key Vault (Azure) |
| CDN経由のAPIルーティング | `/api/*` パスをバックエンドにプロキシ |

### トラフィックフロー

```
ユーザー
  │
  ▼
CloudFront / Front Door (CDN)
  │
  ├── /* ──────────> S3 / Storage Account (Frontend - React SPA)
  │
  └── /api/* ──────> ALB + ECS Fargate / App Service (Backend - NestJS)
                         │
                         ▼
                     Aurora Serverless / PostgreSQL Flexible Server (DB)
```

---

## 3. AWS インフラストラクチャ

### 3.1 Terraform ファイル構成

| ファイル | 管理リソース |
|---|---|
| `provider.tf` | AWS, Auth0 プロバイダー設定 |
| `variables.tf` | 入力変数定義 |
| `vpc.tf` | VPC, サブネット, ルートテーブル, NAT Gateway |
| `vpc_endpoint.tf` | VPCエンドポイント（プライベートアクセス） |
| `security-group.tf` | セキュリティグループ |
| `s3.tf` | フロントエンド用S3バケット |
| `cloudfront.tf` | CloudFrontディストリビューション |
| `ecr.tf` | Elastic Container Registry |
| `ecs.tf` | ECS Fargate クラスター・サービス・タスク |
| `alb.tf` | Application Load Balancer |
| `aurora_serverless_v2.tf` | Aurora Serverless v2 (PostgreSQL) |
| `bastion.tf` | Bastion ホスト（DB接続用） |
| `auth0.tf` | Auth0 SPAクライアント・リソースサーバー |
| `code-pipeline-backend.tf` | バックエンドCI/CD (CodePipeline) |
| `code-pipeline-frontend.tf` | フロントエンドCI/CD (CodePipeline) |

### 3.2 ネットワーク

**VPC構成:**

| リソース | CIDR / 設定 | AZ |
|---|---|---|
| VPC | `172.16.0.0/16` | - |
| パブリックサブネット | `172.16.1.0/24` | ap-northeast-1a |
| プライベートサブネット 1 | `172.16.2.0/24` | ap-northeast-1a |
| プライベートサブネット 2 | `172.16.3.0/24` | ap-northeast-1c |

**VPCエンドポイント:** AWSサービスへのプライベートアクセス用

### 3.3 フロントエンド (S3 + CloudFront)

| リソース | 設定 |
|---|---|
| S3バケット | 静的Webサイトホスティング、バケット名にランダムサフィックス付与 |
| CloudFront | OAC (Origin Access Control) でS3アクセス |
| SPAルーティング | カスタムエラーレスポンス（403 → 200 `/index.html`） |
| HTTPS | 自動リダイレクト |

**CloudFront ビヘイビア:**

| パスパターン | オリジン | キャッシュ |
|---|---|---|
| `*` (デフォルト) | S3 | 有効 |
| `/api/*` | ALB (VPC Origin) | 無効 |

### 3.4 バックエンド (ECS Fargate)

| 項目 | 値 |
|---|---|
| クラスター | Fargate |
| タスクCPU | 256 (.25 vCPU) |
| タスクメモリ | 512 MB |
| コンテナポート | 3000 |
| コンテナイメージ | ECRから取得 |
| ログ | CloudWatch Logs（保持期間: 7日） |

**ECR (Elastic Container Registry):**
- バックエンドDockerイメージを格納
- ライフサイクルポリシー設定可能

### 3.5 データベース (Aurora Serverless v2)

| 項目 | 値 |
|---|---|
| エンジン | PostgreSQL 16.6 |
| スケーリング | 0.0 - 1.0 ACU |
| 自動停止 | 3600秒後 |
| ストレージ暗号化 | 有効 |
| アクセス | プライベートサブネットのみ |
| 接続文字列保管 | SSM Parameter Store (SecureString) |

### 3.6 ロードバランサー (ALB)

| 項目 | 値 |
|---|---|
| タイプ | Application Load Balancer |
| リスナー | HTTP:80 |
| ターゲット | ECS Fargate タスク |
| ヘルスチェック | `GET /health` |

### 3.7 セキュリティグループ

| SG名 | 用途 | インバウンド |
|---|---|---|
| ALB SG | ロードバランサー | CloudFront → ALB |
| ECS SG | Fargate タスク | ALB → ECS (ポート3000) |
| DB SG | Aurora | ECS → DB (ポート5432) |
| Bastion SG | 踏み台 | 指定IP → Bastion |

### 3.8 CI/CD (CodePipeline)

**バックエンドパイプライン:**

```
Source (GitHub/CodeStar)
  │ トリガー: main ブランチ push + backend/** パスフィルタ
  ▼
Build (CodeBuild)
  │ Docker build → ECR push
  │ imagedefinitions.json 生成
  ▼
Deploy (ECS)
  │ ローリングデプロイ
```

**フロントエンドパイプライン:**

```
Source (GitHub/CodeStar)
  │ トリガー: main ブランチ push + frontend/** パスフィルタ
  ▼
Build (CodeBuild)
  │ yarn install → yarn build
  │ S3アップロード → CloudFrontキャッシュ無効化
```

### 3.9 Auth0

| リソース | 設定 |
|---|---|
| SPAクライアント | authorization_code, implicit, refresh_token |
| リソースサーバー | APIオーディエンス定義 |

---

## 4. Azure インフラストラクチャ

### 4.1 Terraform ファイル構成

| ファイル | 管理リソース |
|---|---|
| `provider.tf` | Azure, AzureAD, Auth0 プロバイダー設定 |
| `variables.tf` | 入力変数定義 |
| `resource-group.tf` | リソースグループ |
| `vnet.tf` | VNet, サブネット |
| `storage-account.tf` | フロントエンド用ストレージアカウント |
| `frontdoor-standard.tf` | Front Door Standard (CDN) |
| `container-registry.tf` | Azure Container Registry |
| `app-service.tf` | App Service (バックエンド) |
| `azure_database.tf` | PostgreSQL Flexible Server |
| `bastion.tf` | Bastion (DB接続用) |
| `key-vault.tf` | Key Vault (シークレット管理) |
| `service-principal.tf` | GitHub Actions用サービスプリンシパル |
| `auth0.tf` | Auth0 SPAクライアント |

### 4.2 ネットワーク

| リソース | 設定 |
|---|---|
| VNet | サブネット分割 |
| App Serviceサブネット | サブネットデリゲーション |
| DBサブネット | サブネットデリゲーション + プライベートDNSゾーン |
| Bastionサブネット | セキュアアクセス用 |

### 4.3 フロントエンド (Storage Account + Front Door)

| リソース | 設定 |
|---|---|
| Storage Account | 静的Webサイトホスティング (`$web` コンテナ) |
| Front Door Standard | CDN配信 |
| SPAルーティング | エラードキュメントに `index.html` を指定 |

**Front Door ルート:**

| ルート | オリジングループ | パスパターン |
|---|---|---|
| Web | Storage Account | `/*` |
| API | App Service | `/api/*` |

**ヘルスプローブ:**
- バックエンドオリジンに対して `GET /health` を実行

### 4.4 バックエンド (App Service)

| 項目 | 値 |
|---|---|
| プラン | Linux, B1 SKU |
| コンテナ | ACRからDockerイメージを取得 |
| 認証 | System-assigned Managed Identity (AcrPull ロール) |
| VNet統合 | プライベートサブネットに配置 |
| IP制限 | Front Door Backendからのアクセスのみ許可 |

### 4.5 コンテナレジストリ (ACR)

| 項目 | 値 |
|---|---|
| サービス | Azure Container Registry |
| アクセス | App Service Managed Identity (AcrPull) |

### 4.6 データベース (PostgreSQL Flexible Server)

| 項目 | 値 |
|---|---|
| バージョン | PostgreSQL 16 |
| SKU | B_Standard_B1ms |
| ストレージ | 32GB (P4 tier) |
| バックアップ保持 | 7日 |
| パブリックアクセス | 無効 |
| ネットワーク | VNet統合 + プライベートDNSゾーン |

### 4.7 Key Vault

シークレットの一元管理:

| シークレット | 用途 |
|---|---|
| Auth0資格情報 | AUTH0-DOMAIN, AUTH0-CLIENT-ID, AUTH0-AUDIENCE |
| GitHub Actions OIDC | AZURE-CLIENT-ID, AZURE-TENANT-ID等 |
| DB接続文字列 | DATABASE_URL |
| デプロイ設定 | ACR-NAME, APP-SERVICE-NAME, RESOURCE-GROUP-NAME等 |
| フロントエンド設定 | FRONTEND-STORAGE-ACCOUNT-NAME, API-BASE-URL等 |

**アクセスポリシー:**
- Terraform実行ユーザー
- GitHub Actions サービスプリンシパル
- App Service Managed Identity

### 4.8 監視 (Log Analytics)

| リソース | 設定 |
|---|---|
| Log Analytics Workspace | ログ集約 |
| 診断設定 | App Service → コンソールログ, アプリログ, HTTPログ, メトリクス |

### 4.9 CI/CD (GitHub Actions)

**認証方式:** OIDC（フェデレーテッド資格情報、静的シークレット不要）

**バックエンドデプロイ (`deploy-backend.yaml`):**

```
Checkout
  ▼
Azure Login (OIDC)
  ▼
Key Vaultからシークレット取得
  ▼
ACR Login
  ▼
Docker Build & Push (SHA + latest タグ)
  ▼
App Service コンテナ設定更新
  ▼
App Service 再起動
```

**フロントエンドデプロイ (`deploy-frontend.yaml`):**

```
Checkout
  ▼
Node.js 23.1 セットアップ
  ▼
Azure Login (OIDC)
  ▼
Key Vaultからシークレット取得（Auth0設定, API URL等）
  ▼
Yarn install → Build
  ▼
Azure Blob Storage ($web) にアップロード
  ▼
Front Door キャッシュパージ
```

**トリガー:** `workflow_dispatch`（手動実行）

### 4.10 サービスプリンシパル

| 項目 | 設定 |
|---|---|
| 用途 | GitHub Actions のAzure認証 |
| 認証方式 | フェデレーテッド資格情報 (OIDC) |
| 対象ブランチ | `target-branch` 変数で指定 |

---

## 5. AWS / Azure リソース対応表

| 機能 | AWS | Azure |
|---|---|---|
| CDN | CloudFront | Front Door Standard |
| フロントエンドホスティング | S3 | Storage Account (静的Web) |
| バックエンド実行環境 | ECS Fargate | App Service (Linux) |
| コンテナレジストリ | ECR | ACR |
| データベース | Aurora Serverless v2 | PostgreSQL Flexible Server |
| シークレット管理 | SSM Parameter Store | Key Vault |
| ネットワーク | VPC | VNet |
| 踏み台 | EC2 Bastion | Azure Bastion |
| CI/CD | CodePipeline + CodeBuild | GitHub Actions |
| 認証基盤 | Auth0 (Terraform管理) | Auth0 (Terraform管理) |
| 監視 | CloudWatch Logs | Log Analytics Workspace |
| CI/CD認証 | CodeStar Connection | OIDC (フェデレーテッド) |

## 6. Terraform 変数

### 6.1 共通変数

| 変数名 | デフォルト | 説明 |
|---|---|---|
| `auth0_domain` | (必須) | Auth0テナントドメイン |
| `auth0_client_id` | (必須) | Auth0 Client ID |
| `auth0_client_secret` | (必須) | Auth0 Client Secret |
| `github-repository-name` | (必須) | GitHubリポジトリ名 |
| `app-name` | `sandbox-aws` / `sandbox` | アプリケーション名プレフィックス |
| `environment` | `dev` | 環境名 |
| `frontend-src-root` | `frontend/sandbox-frontend` | フロントエンドのソースパス |
| `backend-src-root` | `backend/sandbox-backend` | バックエンドのソースパス |
| `target-branch` | `main` | CI/CDトリガー対象ブランチ |
| `api-base-path` | `/api/*` | バックエンドAPIのベースパス |
| `health-check-path` | `/health` | ヘルスチェックパス |
| `api-expose-port` | `3000` | コンテナ公開ポート |
| `local-pc-ip-addresses` | `[]` | 接続元IPアドレス（Bastion用） |

### 6.2 AWS固有変数

| 変数名 | デフォルト | 説明 |
|---|---|---|
| `codestar-connection-arn` | (必須) | CodeStar接続ARN |
| `vpc_cidr_block` | `172.16.0.0/16` | VPC CIDRブロック |
| `subnet_public1a_cidr_block` | `172.16.1.0/24` | パブリックサブネットCIDR |
| `subnet_private1a_cidr_block` | `172.16.2.0/24` | プライベートサブネット1 CIDR |
| `subnet_private1c_cidr_block` | `172.16.3.0/24` | プライベートサブネット2 CIDR |

### 6.3 Azure固有変数

| 変数名 | デフォルト | 説明 |
|---|---|---|
| `azure-subscription-id` | (必須) | AzureサブスクリプションID |
| `location` | `japaneast` | Azureリージョン |
| `public-key-vault-name` | `""` | 公開Key Vault名 |
| `public-key-vault-rg-name` | `""` | 公開Key Vaultリソースグループ名 |
| `public-key-vault-secret` | `""` | 公開Key Vaultシークレット |

## 7. デプロイ手順

### 7.1 初回セットアップ

```bash
# AWS
cd iac/aws
cp terraform.tfvars.example terraform.tfvars  # 変数を編集
terraform init
terraform plan
terraform apply

# Azure
cd iac/azure
cp terraform.tfvars.example terraform.tfvars  # 変数を編集
terraform init
terraform plan
terraform apply
```

### 7.2 アプリケーションデプロイ

**AWS:**
- `main` ブランチへのpushでCodePipelineが自動トリガー
- バックエンド: `backend/**` のファイル変更でトリガー
- フロントエンド: `frontend/**` のファイル変更でトリガー

**Azure:**
- GitHub Actionsワークフローを手動実行 (`workflow_dispatch`)
- Key Vaultから動的に設定値を取得

## 8. セキュリティ設計

| セキュリティ施策 | AWS | Azure |
|---|---|---|
| DB非公開 | プライベートサブネット | VNet統合 + パブリックアクセス無効 |
| シークレット管理 | SSM Parameter Store (SecureString) | Key Vault |
| CDNオリジン保護 | OAC (S3), VPC Origin (ALB) | IP制限 (Front Door Backend) |
| CI/CD認証 | CodeStar Connection | OIDC (フェデレーテッド資格情報) |
| コンテナレジストリ | プライベートECR | Managed Identity (AcrPull) |
| 通信暗号化 | HTTPS リダイレクト | HTTPS (Front Door) |
| ストレージ暗号化 | Aurora暗号化有効 | - |
| アクセス制御 | セキュリティグループ | NSG + サブネットデリゲーション |
