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
CloudFront (+ WAF v2) / Front Door (CDN)
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
| `vpc_flow_log.tf` | VPCフローログ（S3出力） |
| `security-group.tf` | セキュリティグループ |
| `s3.tf` | フロントエンド用S3バケット |
| `cloudfront.tf` | CloudFrontディストリビューション |
| `ecr.tf` | バックエンド用 Elastic Container Registry |
| `ecs.tf` | ECS Fargate クラスター・サービス・タスク定義 |
| `ecs_logs.tf` | ECSログ用S3バケット・Fluent Bit用ECRリポジトリ・IAMポリシー |
| `alb.tf` | Application Load Balancer |
| `aurora_serverless_v2.tf` | Aurora Serverless v2 (PostgreSQL) |
| `aws_backup.tf` | AWS Backup (Auroraクラスタの長期バックアップ) |
| `bastion.tf` | Bastion ホスト（DB接続用） |
| `auth0.tf` | Auth0 SPAクライアント・リソースサーバー |
| `code-pipeline-backend.tf` | バックエンドCI/CD (CodePipeline) |
| `code-pipeline-frontend.tf` | フロントエンドCI/CD (CodePipeline) |
| `athena_alb_logs.tf` | ALBアクセスログ用 Glue テーブル・Athena ワークグループ |
| `athena_vpc_flow_logs.tf` | VPCフローログ用 Glue テーブル・Athena ワークグループ |
| `athena_ecs_logs.tf` | ECSコンテナログ用 Glue テーブル・Athena ワークグループ |
| `cloudfront_logs.tf` | CloudFrontアクセスログ用S3バケット・v2 CW Logs Delivery設定 |
| `waf.tf` | AWS WAF v2 WebACL (CloudFront scope) + WAFログ用S3バケット |
| `cloudwatch_alarms.tf` | CloudWatch アラーム (ECS/Aurora) + SNS トピック |
| `athena_cloudfront_logs.tf` | CloudFrontアクセスログ用 Glue テーブル・Athena ワークグループ |
| `athena_waf_logs.tf` | WAFログ用 Glue テーブル・Athena ワークグループ |
| `start-stop-resources.tf` | 自動起動・停止（EventBridge Scheduler + Step Functions） |

### 3.2 ネットワーク

**VPC構成:**

| リソース | 変数名 | デフォルト値 | AZ |
|---|---|---|---|
| VPC | `vpc_cidr_block` | `172.16.0.0/16` | - |
| パブリックサブネット | `subnet_public1a_cidr_block` | `172.16.1.0/24` | ap-northeast-1a |
| プライベートサブネット 1 | `subnet_private1a_cidr_block` | `172.16.2.0/24` | ap-northeast-1a |
| プライベートサブネット 2 | `subnet_private1c_cidr_block` | `172.16.3.0/24` | ap-northeast-1c |

> **⚠️ CIDRアドレスの設計について**
> デフォルト値はそのまま使用できますが、以下のケースでは変更が必要です。
> - 既存VPCやオンプレミスネットワークとVPCピアリング / VPN接続する場合（CIDRの重複不可）
> - 社内ネットワークのアドレス体系に合わせる必要がある場合
>
> 変更する場合は `terraform.tfvars` で上書きしてください。サブネットはVPC CIDRの範囲内に収めること。

**VPCエンドポイント:** NAT Gatewayを経由せずAWSサービスへプライベートアクセスするため

| エンドポイント | タイプ | 用途 |
|---|---|---|
| `ssm` | Interface | Session Manager (Bastion) |
| `ssmmessages` | Interface | Session Manager メッセージ通信 |
| `ec2messages` | Interface | EC2メッセージ通信 |
| `ecr.api` | Interface | ECS FargateのECR APIアクセス |
| `ecr.dkr` | Interface | ECS FargateのDockerイメージPull |
| `logs` | Interface | ECSコンテナログのCloudWatch Logs送信 |
| `s3` | Gateway（無料） | ECRイメージレイヤー(S3格納)取得 |

> Auth0 JWKSエンドポイント等の外部サービス呼び出しはVPCエンドポイントで代替できないため、NAT Gatewayは引き続き必要。

### 3.3 フロントエンド (S3 + CloudFront)

| リソース | 設定 |
|---|---|
| S3バケット | 静的Webサイトホスティング、バケット名にランダムサフィックス付与 |
| CloudFront | OAC (Origin Access Control) でS3アクセス |
| SPAルーティング | カスタムエラーレスポンス（403 → 200 `/index.html`） |
| HTTPS | 自動リダイレクト |

**CloudFront ビヘイビア:**

| 優先度 | パスパターン | オリジン | キャッシュポリシー | 備考 |
|---|---|---|---|---|
| デフォルト | `*` | S3 | Managed-CachingOptimized (有効) | 静的アセット |
| 1 | `/index.html` | S3 | Managed-CachingDisabled (無効) | 再デプロイ時に常に最新を返すため |
| 2 | `/api/*` | ALB (VPC Origin) | Managed-CachingDisabled (無効) | 全ヘッダをオリジンへ転送 |

> `/index.html` は CloudFront でのキャッシュ無効化に加え、S3 アップロード時に `Cache-Control: no-store, no-cache` を付与することでブラウザキャッシュも抑止している。

### 3.4 バックエンド (ECS Fargate)

| 項目 | 値 |
|---|---|
| クラスター | Fargate |
| タスクCPU | 256 (.25 vCPU) |
| タスクメモリ | 512 MB |
| コンテナポート | 3000 |
| コンテナイメージ | ECRから取得 |
| ログ | FireLens (Fluent Bit) 経由で CloudWatch Logs（7日）と S3 に同時出力 |

**ECR (Elastic Container Registry):**
- バックエンドDockerイメージ（`dev/sandbox-aws-backend`）
- Fluent Bit カスタムイメージ（`dev/fluent-bit`）— `iac/aws/fluent-bit/` でビルド・管理

**FireLens (Fluent Bit) ログルーティング:**

| 出力先 | 内容 | 保持 |
|---|---|---|
| CloudWatch Logs | テキスト形式（ヘルスチェック除外、ANSIカラー除去） | 7日 |
| S3 | JSON形式（Athenaクエリ用） | ライフサイクルポリシーで階層管理 |

> Fluent Bit 設定ファイル（`extra.conf`）の変更時はカスタムイメージの再ビルドが必要。手順は [運用コマンドリファレンス](../docs/operations.md) を参照。

### 3.5 データベース (Aurora Serverless v2)

| 項目 | 値 |
|---|---|
| エンジン | PostgreSQL 16.6 |
| スケーリング | 0.0 - 1.0 ACU |
| 自動停止 | 3600秒後 |
| ストレージ暗号化 | 有効 |
| アクセス | プライベートサブネットのみ |
| 接続文字列保管 | SSM Parameter Store (SecureString) |
| コネクションプール | `db-connection-limit` / `db-pool-timeout` 変数で指定（Prisma） |
| 長期バックアップ | AWS Backup (専用Vault・日次・30日保持) — 3.5.1参照 |

#### 3.5.1 バックアップ (AWS Backup)

Aurora自動バックアップ（最大35日）とは別系統で、AWS Backup Vault単位でアクセス制御・保持期間を管理する。

| 項目 | 値 |
|---|---|
| Backup Vault | `{app-name}-{environment}-aurora-vault`（専用Vault） |
| 暗号化キー | `aws/backup` (AWS管理KMSキー) |
| スケジュール | 日次 02:00 JST（`cron(0 2 * * ? *)` / `Asia/Tokyo`） |
| 保持期間 | 30日 |
| start_window / completion_window | 60分 / 240分 |
| クロスリージョンコピー | 無効 |
| Cold Storage遷移 | 無効 |
| 対象リソース | `aws_rds_cluster.cluster` |
| IAMロール | `AWSBackup-{app-name}-{environment}-role`（`...ForBackup` / `...ForRestores` 管理ポリシー） |

> auto-stop (13:00 JST) で停止状態にある時間帯にバックアップが走るが、停止中Auroraクラスタもスナップショット取得は可能(`CreateDBClusterSnapshot`)。

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

### 3.8 WAF (AWS WAF v2)

CloudFront に紐付けた WAF WebACL でマネージドルールによる自動防御を行う。

| 項目 | 値 |
|---|---|
| スコープ | CLOUDFRONT（グローバル、us-east-1 API で管理） |
| デフォルトアクション | ALLOW |
| ルールグループ | AWSManagedRulesCommonRuleSet (priority 10) |
| ルールグループ | AWSManagedRulesKnownBadInputsRuleSet (priority 20) |
| ルールグループ | AWSManagedRulesAmazonIpReputationList (priority 30) |
| サンプルリクエスト | 有効（全ルール） |

**WAFログ:**

- S3バケット（us-east-1）: `aws-waf-logs-{app-name}-{environment}-{suffix}` （バケット名プレフィックス必須）
- 形式: NDJSON / gzip圧縮
- Athena テーブル: `{app_name}_{environment}_waf_logs.waf_logs`（ap-northeast-1 ワークグループから Athena v3 クロスリージョンクエリで参照可）

### 3.9 CloudFrontアクセスログ

CloudWatch Logs Delivery v2 (aws_cloudwatch_log_delivery_*) でS3に配信する。

| 項目 | 値 |
|---|---|
| 配信方式 | v2 CW Logs Delivery（バケットポリシーのみ、ACL不要） |
| 形式 | JSON（CloudFrontフィールド名をそのままJSONキーとして出力） |
| S3バケット | ap-northeast-1（`{app-name}-{environment}-cf-logs-{suffix}`） |
| パス | `AWSLogs/{account}/CloudFront/{dist-id}/{yyyy}/{MM}/{dd}/{HH}/` |
| Athena テーブル | `{app_name}_{environment}_cloudfront_logs.cloudfront_access_logs` |

> レガシー方式（`logging_config`）は `block_public_acls = true` と競合するため採用しない。

### 3.10 監視アラーム (CloudWatch Alarms)

ECS・Aurora の主要メトリクスを監視し、SNS トピックへ通知する。

| アラーム | メトリクス | 閾値 |
|---|---|---|
| `ecs-cpu-high` | ECS CPUUtilization | > 80% |
| `ecs-memory-high` | ECS MemoryUtilization | > 80% |
| `aurora-connections-high` | DatabaseConnections (Maximum) | > 70 |
| `aurora-cpu-high` | CPUUtilization | > 80% |
| `aurora-acu-high` | ACUUtilization | > 80% |
| `aurora-freeable-memory-low` | FreeableMemory | < 200 MiB |
| `aurora-free-local-storage-low` | FreeLocalStorage (Minimum) | < 512 MiB |
| `aurora-volume-bytes-high` | VolumeBytesUsed | > 100 GiB |

- 全アラーム: `evaluation_periods = 2`, `treat_missing_data = "notBreaching"`
- SNS トピック: `{app-name}-{environment}-alarms`（サブスクリプションは Terraform 管理外・手動登録）

### 3.11 CI/CD (CodePipeline)

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
  │ S3アップロード (index.html を除く全ファイル: aws s3 sync --delete --exclude "index.html")
  │ index.html アップロード (Cache-Control: no-store, no-cache)
  │ CloudFrontキャッシュ無効化 (/*)
```

### 3.12 Auth0

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
| WAF | AWS WAF v2 (CloudFront scope) | — |
| フロントエンドホスティング | S3 | Storage Account (静的Web) |
| バックエンド実行環境 | ECS Fargate | App Service (Linux) |
| コンテナレジストリ | ECR | ACR |
| データベース | Aurora Serverless v2 | PostgreSQL Flexible Server |
| DB長期バックアップ | AWS Backup (専用Vault) | PostgreSQL Flexible Server組込み (7日保持) |
| シークレット管理 | SSM Parameter Store | Key Vault |
| ネットワーク | VPC | VNet |
| 踏み台 | EC2 Bastion | Azure Bastion |
| CloudFrontアクセスログ | S3 (v2 CW Logs Delivery) | — |
| WAFログ | S3 (direct logging) | — |
| 監視アラーム | CloudWatch Alarms + SNS | — |
| CI/CD | CodePipeline + CodeBuild | GitHub Actions |
| 認証基盤 | Auth0 (Terraform管理) | Auth0 (Terraform管理) |
| 監視ログ | CloudWatch Logs | Log Analytics Workspace |
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
| `db-connection-limit` | `5` | Prismaコネクションプール上限（設定指針は README 参照） |
| `db-pool-timeout` | `15` | Prismaコネクション空き待ちタイムアウト（秒） |

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
| バックアップ暗号化 | AWS Backup Vault (`aws/backup` KMSキー) | PostgreSQLサービス組込み |
| アクセス制御 | セキュリティグループ | NSG + サブネットデリゲーション |
