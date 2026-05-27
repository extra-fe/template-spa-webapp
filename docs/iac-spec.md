# IaC (Infrastructure as Code) 仕様書

## 1. 概要

AWS、Azure、GCP の 3 クラウドに同一アプリケーションをデプロイするためのインフラ定義。Terraformで全リソースを管理し、CI/CDパイプラインによる自動デプロイを実現する。

| 項目 | 値 |
|---|---|
| IaCツール | Terraform 1.13.5 |
| 対象クラウド | AWS, Azure, GCP |
| 認証基盤 | Auth0（3クラウド共通） |
| ソースパス | `iac/aws/`, `iac/azure/`, `iac/gcp/` |

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
CloudFront (+ WAF v2) / Front Door / External Application LB (+ Cloud Armor)
  │
  ├── /* ──────────> S3 / Storage Account / Cloud Storage (Frontend - React SPA)
  │
  └── /api/* ──────> ALB + ECS Fargate / App Service / Cloud Run (Backend - NestJS)
                         │
                         ▼
                     Aurora Serverless / PostgreSQL Flexible Server / Cloud SQL for PostgreSQL (DB)
```

---

## 3. AWS インフラストラクチャ

### 3.1 Terraform ファイル構成

| ファイル | 管理リソース |
|---|---|
| `provider.tf` | AWS, Auth0 プロバイダー設定 |
| `variables.tf` | 入力変数定義 |
| `vpc.tf` | VPC, プライベートサブネット, ルートテーブル, Regional NAT Gateway |
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
| プライベートサブネット 1 | `subnet_private1a_cidr_block` | `172.16.2.0/24` | ap-northeast-1a |
| プライベートサブネット 2 | `subnet_private1c_cidr_block` | `172.16.3.0/24` | ap-northeast-1c |

> Regional NAT Gateway (automatic mode) を使用しているため、NAT専用のパブリックサブネットは持たない。AWSがVPC配下のENI出現を検知して必要なAZへ自動拡張し、IPアドレスも自動払い出しされる。

> **⚠️ CIDRアドレスの設計について**
> デフォルト値はそのまま使用できますが、以下のケースでは変更が必要です。
> - 既存VPCやオンプレミスネットワークとVPCピアリング / VPN接続する場合（CIDRの重複不可）
> - 社内ネットワークのアドレス体系に合わせる必要がある場合
>
> 変更する場合は `terraform.tfvars` で上書きしてください。サブネットはVPC CIDRの範囲内に収めること。

**VPCエンドポイント:** Regional NAT Gatewayを経由せずAWSサービスへプライベートアクセスするため

| エンドポイント | タイプ | 用途 |
|---|---|---|
| `ssm` | Interface | Session Manager (Bastion) |
| `ssmmessages` | Interface | Session Manager メッセージ通信 |
| `ec2messages` | Interface | EC2メッセージ通信 |
| `ecr.api` | Interface | ECS FargateのECR APIアクセス |
| `ecr.dkr` | Interface | ECS FargateのDockerイメージPull |
| `logs` | Interface | ECSコンテナログのCloudWatch Logs送信 |
| `s3` | Gateway（無料） | ECRイメージレイヤー(S3格納)取得 |

> Auth0 JWKSエンドポイント等の外部サービス呼び出しはVPCエンドポイントで代替できないため、Regional NAT Gatewayは引き続き必要。

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
| コネクションプール | `db-connection-limit` / `db-pool-timeout` 変数で指定（Prisma） — 3.5.1参照 |
| 長期バックアップ | AWS Backup (専用Vault・日次・30日保持) — 3.5.2参照 |

#### 3.5.1 コネクションプール設定の指針

`iac/aws/variables.tf` の以下の変数でPrismaのコネクションプールを調整する。

| 変数 | デフォルト | 説明 |
|---|---|---|
| `db-connection-limit` | `5` | Prismaが1プロセスで保持するコネクション数の上限 |
| `db-pool-timeout` | `15` | コネクション空き待ちのタイムアウト（秒） |

**`db-connection-limit` の決め方:**

Aurora Serverless v2 の最大コネクション数はACUに比例する。

| インスタンス / ACU | メモリ | 最大コネクション数（概算） |
|---|---|---|
| Serverless v2 0.5 ACU | 1 GiB | 約 45 |
| Serverless v2 1.0 ACU | 2 GiB | 約 90 |
| Serverless v2 2.0 ACU | 4 GiB | 約 180 |
| db.t3.medium | 4 GiB | 約 450 |
| db.m5.large | 8 GiB | 約 900 |
| db.m5.xlarge | 16 GiB | 約 1,800 |
| db.m5.2xlarge | 32 GiB | 約 3,600 |

> 正確な値は `LEAST({DBInstanceClassMemory / 9531392}, 5000)` で計算される。

以下の条件を満たす値を設定すること。

```
ECSタスク最大数 × db-connection-limit ≦ Aurora最大コネクション数 × 0.8 (安全マージン)
```

例: ACU最大 1.0（最大コネクション90）、ECSタスク最大10台の場合
```
10 × db-connection-limit ≦ 90 × 0.8 = 72
→ db-connection-limit ≦ 7  （余裕を見て 5 程度を推奨）
```

#### 3.5.2 バックアップ (AWS Backup)

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

> auto-stop (21:00 JST) で停止状態にある時間帯にバックアップが走るが、停止中Auroraクラスタもスナップショット取得は可能(`CreateDBClusterSnapshot`)。

### 3.6 ロードバランサー (ALB)

| 項目 | 値 |
|---|---|
| タイプ | Application Load Balancer |
| リスナー | HTTP:80 |
| ターゲット | ECS Fargate タスク |
| ヘルスチェック | `GET /health` |

### 3.7 セキュリティグループ

インバウンド・アウトバウンドともに最小権限で構成する。

| SG名 | 用途 | インバウンド | アウトバウンド |
|---|---|---|---|
| ALB SG | ロードバランサー | CloudFront VPC Origin → TCP 80 | TCP `api-expose-port` → ECS SG のみ |
| ECS SG | Fargate タスク | ALB → TCP 3000 | TCP 443 to `0.0.0.0/0`（VPCエンドポイント＋外部SaaS）/ TCP 5432 → DB SG |
| DB SG | Aurora | ECS → TCP 5432 / Bastion → TCP 5432 | **なし**（Aurora はアウトバウンド接続を開始しない） |
| Bastion SG | 踏み台 | 指定IP → TCP 0-65535 | TCP 443 → VPC CIDR（SSMエンドポイント）/ TCP 5432 → DB SG |
| SSM endpoint SG | VPCインターフェイスエンドポイント | VPC CIDR → TCP 443 | TCP 443 → VPC CIDR |

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

### 3.13 自動起動・停止 (EventBridge Scheduler + Step Functions)

開発コスト削減のため、EventBridge Scheduler + Step Functions でリソースを自動制御する。

| スケジュール | 時刻（JST） | 対象 | デフォルト |
|---|---|---|---|
| Auto-stop | 毎日 21:00 | ECS（タスク数→0）→ Aurora 停止 → Bastion 停止 | **有効** |
| Auto-start | 土日 7:00 | Bastion 起動 → Aurora 起動（12分待機）→ ECS（タスク数→1） | 無効 |

> Auto-start はデフォルト無効。平日も自動起動したい場合は AWS コンソール（EventBridge Scheduler）または Terraform の `state` を `"ENABLED"` に変更する。

**手動起動・停止**

Step Functions コンソールから対象のステートマシンを選択し「実行を開始」する。

| ステートマシン名 | 操作 |
|---|---|
| `exec-auto-stop-{app-name}-{environment}` | 停止 |
| `exec-auto-start-{app-name}-{environment}` | 起動 |

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
Node.js 22.15.0 セットアップ
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

## 5. GCP インフラストラクチャ

### 5.1 Terraform ファイル構成

| ファイル | 管理リソース |
|---|---|
| `provider.tf` | Google Cloud, google-beta, Auth0 プロバイダ設定 |
| `variables.tf` | 入力変数定義 / 公開URL local |
| `vpc.tf` | VPC ネットワーク, サブネット, Cloud NAT, Serverless VPC Access コネクタ, Private Service Access |
| `firewall.tf` | VPC Firewall ルール (IAP / Bastion / DB) |
| `cloud_storage.tf` | フロントエンド用 Cloud Storage バケット |
| `load_balancer.tf` | External Application LB + Cloud CDN + URL マップ + Serverless NEG |
| `cloud_armor.tf` | Cloud Armor セキュリティポリシー (WAF 相当) |
| `artifact_registry.tf` | バックエンド用 Artifact Registry |
| `cloud_run.tf` | Cloud Run サービス + ランタイム SA + IAM |
| `cloud_sql.tf` | Cloud SQL for PostgreSQL (Private IP) + DB / ユーザ |
| `secret_manager.tf` | DATABASE_URL を格納する Secret Manager シークレット |
| `bastion.tf` | Compute Engine Bastion VM (IAP TCP forwarding 経由) |
| `auth0.tf` | Auth0 SPA クライアント・リソースサーバー |
| `workload_identity.tf` | GitHub Actions 用 Workload Identity Federation (OIDC) + デプロイ SA × 2 + IAM |
| `outputs.tf` | LB IP / GitHub Actions Variables / Secrets を JSON で公開 |
| `monitoring_alerts.tf` | Cloud Monitoring アラートポリシー + Pub/Sub 通知トピック (Email チャネルのみ) |
| `start-stop-resources.tf` | 自動起動・停止 (Cloud Scheduler + Cloud Workflows) |
| `bigquery_log_sinks.tf` | Cloud Logging → BigQuery sink (LB / Cloud Run / Cloud Armor / VPC Flow Logs) |
| `setup-github-env.ps1` | terraform output → gh CLI で GitHub Environment Variables / Secrets を一括登録するヘルパースクリプト |

### 5.2 ネットワーク

**VPC 構成:**

| リソース | 変数名 | デフォルト値 | リージョン |
|---|---|---|---|
| VPC | (auto subnet 無効) | — | グローバル |
| プライマリサブネット | `subnet_primary_cidr_block` | `172.16.2.0/24` | asia-northeast1 |
| Serverless VPC コネクタサブネット | `subnet_connector_cidr_block` | `172.16.4.0/28` (`/28` 必須) | asia-northeast1 |
| Private Service Access レンジ | `psa_range_cidr_block` | `172.16.16.0/20` | グローバル予約 |

**Cloud NAT (Cloud Router):** AWS の Regional NAT Gateway / Azure の VNet egress 相当。Bastion 等 VPC 内インスタンスのアウトバウンドインターネット通信を NAT。

**Private Google Access:** プライマリサブネットで有効化。AWS の VPCエンドポイント (Interface) 相当。NAT 経由せず Google API (Artifact Registry / Secret Manager / Cloud Logging 等) にプライベートアクセス。

**Serverless VPC Access コネクタ:** Cloud Run → VPC 内の Cloud SQL Private IP に到達するための論理経路。AWS の ECS awsvpc モード相当。

**Private Service Access:** Service Networking ピアリングを介して Cloud SQL の Private IP を VPC 内ネットワークに公開。

### 5.3 フロントエンド (Cloud Storage + LB + Cloud CDN)

| リソース | 設定 |
|---|---|
| Cloud Storage バケット | uniform_bucket_level_access + public_access_prevention=inherited + allUsers に `roles/storage.objectViewer` |
| SPA ルーティング | `notFoundPage = "index.html"` (AWS の `403 → /index.html` 相当) |
| Backend Bucket (Cloud CDN) | `cache_mode = USE_ORIGIN_HEADERS` で `index.html` の `no-store, no-cache` を尊重 |
| LB | External Application LB (EXTERNAL_MANAGED) |
| HTTPS 証明書 | Google Managed SSL Certificate (`lb-domain` 設定時のみ作成・自動更新) |
| HTTP リダイレクト | `lb-domain` 設定時は `MOVED_PERMANENTLY_DEFAULT` (301) で HTTPS 強制 / 未設定時は HTTP 直接応答 (PoC 用) |

> Cloud CDN 配信のため `cloud-cdn-fill` SA に IAM 付与する代わりに allUsers public viewer に変更。Backend Bucket + Cloud CDN 静的アセット配信の標準パターンで、AWS S3 + OAC とは設計思想が異なる。

**URL マップ:**

| 優先度 | パス | ターゲット | 備考 |
|---|---|---|---|
| デフォルト | `*` | Backend Bucket (GCS) | Cloud CDN 経由で静的アセット配信 |
| 1 | `/api/*` | Backend Service → Serverless NEG → Cloud Run | CDN なし、Cloud Armor 適用 |

**セキュリティヘッダ:** URL マップの `header_action` で HSTS / X-Content-Type-Options / X-Frame-Options / Referrer-Policy / X-XSS-Protection / Permissions-Policy / CSP を一括付与 (AWS の Response Headers Policy 相当)。

### 5.4 バックエンド (Cloud Run)

| 項目 | 値 |
|---|---|
| 実行環境 | Cloud Run v2 (フルマネージドサーバーレス) |
| CPU | 1 vCPU (cpu_idle 有効) |
| メモリ | 512 MiB |
| コンテナポート | 3000 (`api-expose-port` 変数) |
| イメージ | Artifact Registry (`backend:latest` / `backend:$SHORT_SHA`) |
| Ingress | `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` (LB 経由のみ受信) |
| VPC アクセス | Serverless VPC Access コネクタ (egress = PRIVATE_RANGES_ONLY) |
| ヘルスチェック | startup_probe / liveness_probe = `GET /health` |
| ログ | Cloud Logging (Cloud Run 標準出力) → BigQuery sink で分析 |
| シークレット | DATABASE_URL = Secret Manager `secret_key_ref` |
| ランタイム SA | `${app-name}-${environment}-run` (artifactregistry.reader / secretmanager.secretAccessor / cloudsql.client / logging.logWriter) |

> `template[0].containers[0].image` を `lifecycle.ignore_changes` 対象にし、GitHub Actions 経由のリビジョン更新と Terraform の管理境界を分離している (AWS の `aws_ecs_service.task_definition` ignore と同じ思想)。初回 apply 時は placeholder の `us-docker.pkg.dev/cloudrun/container/hello` で起動し、後続の GitHub Actions デプロイで本番イメージに差し替わる。

### 5.5 データベース (Cloud SQL for PostgreSQL)

| 項目 | 値 |
|---|---|
| エンジン | PostgreSQL 16 |
| マシンタイプ | `db-custom-1-3840` (1 vCPU / 3.75GB)、`db-tier` 変数で変更可 |
| 可用性 | ZONAL |
| ディスク | PD_SSD 10GB (自動拡張) |
| パブリックアクセス | 無効 (`ipv4_enabled = false`) |
| Private IP | Service Networking ピアリング経由 |
| 自動バックアップ | 02:00 JST 開始、30 件保持、PITR 有効 (7 日) |
| クエリインサイト | 有効 (slow query = 1s 以上ログ) |
| 接続情報 | DATABASE_URL を Secret Manager に格納 |
| コネクションプール | `db-connection-limit` / `db-pool-timeout` 変数で Prisma 側を調整 |

> Aurora Serverless v2 のような ACU 単位の自動スケーリングはないが、`db-tier` を変更することで縦スケールは可能。Aurora 同等の柔軟性が必要な場合は AlloyDB への切替を検討する。

### 5.6 ロードバランサー (External Application LB)

| 項目 | 値 |
|---|---|
| タイプ | External HTTPS Application LB (Global, EXTERNAL_MANAGED) |
| フロントエンド | グローバル静的 IP + HTTPS:443 / HTTP:80 |
| HTTP 動作 | `lb-domain` 設定時は HTTPS リダイレクト / 未設定時は HTTP 直接応答 (PoC 用) |
| バックエンド (frontend) | Backend Bucket (GCS) + Cloud CDN 有効 |
| バックエンド (backend) | Backend Service + Serverless NEG (Cloud Run) |
| ヘルスチェック | Serverless NEG では不要 (Cloud Run 側 probe を使用) |
| Cloud Armor | Backend Service / Backend Bucket の双方にアタッチ |

### 5.7 Firewall ルール

| ルール | 方向 | プロトコル/ポート | ソース/ターゲット |
|---|---|---|---|
| `bastion-ssh-from-iap` | INGRESS | TCP 22 | source: 35.235.240.0/20 (IAP), target tag: bastion |
| `bastion-egress-db` | EGRESS | TCP 5432 | dest: PSA range, target tag: bastion |
| `bastion-egress-https` | EGRESS | TCP 443 | dest: 0.0.0.0/0, target tag: bastion |
| `deny-all-ingress` | INGRESS | ALL | source: 0.0.0.0/0, priority 65534 (デフォルト拒否の明示) |

> Cloud Run → Cloud SQL は VPC Connector 経由で PSA range の Private IP に到達する。Cloud SQL Private IP 側は GCP マネージドネットワークで、VPC Firewall の制御対象外。

### 5.8 Cloud Armor (WAF)

LB Backend Service (API / Cloud Run) にアタッチしたセキュリティポリシーで攻撃を遮断。

> Cloud Armor の `edge_security_policy` (Backend Bucket 用) は preconfigured WAF (SQLi/XSS 等) を**サポートしない**制約があるため、フル WAF は API 側 (Backend Service) のみに適用。静的アセットは攻撃面が小さいため WAF より rate-limit/DDoS 対策で十分という設計判断。

| 優先度 | ルール | アクション |
|---|---|---|
| 1000 | SQL Injection (`sqli-v33-stable`) | deny(403) |
| 1100 | XSS (`xss-v33-stable`) | deny(403) |
| 1200 | Local File Inclusion (`lfi-v33-stable`) | deny(403) |
| 1300 | Remote Code Execution (`rce-v33-stable`) | deny(403) |
| 1400 | Protocol attack (`protocolattack-v33-stable`) | deny(403) |
| 1500 | Scanner detection (`scannerdetection-v33-stable`) | deny(403) |
| 2000 | `/api/*` レート制限 (2000 req/5min/IP) | rate_based_ban → deny(429), ban_duration=600s |
| 2147483647 | デフォルト | allow |

**Adaptive Protection (Layer 7 DDoS):** 有効化。ML ベースの異常検知。

**ログ:** `log_level = VERBOSE`。LB request log の `jsonPayload.enforcedSecurityPolicy.*` フィールドに記録され、BigQuery sink (`*_armor_logs`) に転送される。

### 5.9 監視アラート (Cloud Monitoring)

Cloud Run / Cloud SQL の主要メトリクスを監視し、Pub/Sub トピック + Email チャネルへ通知する。

| アラーム | メトリクス | 閾値 |
|---|---|---|
| `run-cpu-high` | Cloud Run container CPU utilization | > 80% (P99) |
| `run-memory-high` | Cloud Run container memory utilization | > 80% (P99) |
| `sql-cpu-high` | Cloud SQL CPU utilization | > 80% (mean) |
| `sql-memory-high` | Cloud SQL memory utilization | > 80% (mean) |
| `sql-connections-high` | PostgreSQL `num_backends` | > 70 (max) |
| `sql-disk-high` | Cloud SQL disk utilization | > 80% (mean) |
| `sql-disk-bytes-high` | Cloud SQL disk bytes used | > 100 GiB (max, 5分粒度) |

- 評価間隔: 60秒、評価期間: 120秒 (連続 2 回超過で通知)
- Pub/Sub トピック: `${app-name}-${environment}-alarms` (購読は Terraform 管理外)
- Email チャネル: `alert-notification-emails` 変数の各アドレス

### 5.10 CI/CD (GitHub Actions + Workload Identity Federation)

Azure 側と同じ思想 (`workflow_dispatch` + OIDC) で統一。Cloud Build / Cloud Deploy / Cloud Build GitHub Connection は使わず、GitHub Actions の OIDC トークンを直接 GCP に持ち込んでデプロイ SA を impersonation する。

**Workload Identity Federation 構成:**

| リソース | 役割 |
|---|---|
| Workload Identity Pool | `${app-name}-${environment}-gh` |
| OIDC Provider | `github` (issuer = `https://token.actions.githubusercontent.com`) |
| `attribute_condition` | `assertion.repository == "<github-repository-name>"` (他リポジトリ拒否) |
| デプロイ SA (backend) | `${app-name}-${environment}-ga-be` |
| デプロイ SA (frontend) | `${app-name}-${environment}-ga-fe` |
| WIF binding | `principalSet://.../attribute.environment/<github-environment>` → SA に `roles/iam.workloadIdentityUser` |

> `attribute.environment` を使うことで、GitHub Environment 名 (`gcp-main`) で実行された workflow のみが impersonation 可能。Azure 側の `main` Environment と衝突しないように分離。

**バックエンドパイプライン (`deploy-backend-gcp.yaml`):**

```
GitHub Actions (workflow_dispatch, environment = gcp-main)
  │
  ▼
google-github-actions/auth@v2 (token_format: access_token)
  │ OIDC → STS → SA impersonation → SA access token (1h)
  ▼
docker build & push (latest + $GITHUB_SHA) → Artifact Registry
  ▼
gcloud run services update --image=... → Cloud Run (rolling deploy)
```

**フロントエンドパイプライン (`deploy-frontend-gcp.yaml`):**

```
GitHub Actions (workflow_dispatch, environment = gcp-main)
  │
  ▼
google-github-actions/auth@v2 (token_format: access_token)
  ▼
node 22 + yarn install → yarn build (with VITE_ env injection)
  ▼
gcloud storage rsync ./dist gs://${web} (index.html 除外)
gcloud storage cp ./dist/index.html (Cache-Control: no-store, no-cache)
gcloud compute url-maps invalidate-cdn-cache (/*)
```

**事前準備:**

1. `terraform apply` で WIF + SA + 必要 IAM を作成
2. `terraform output github_actions_variables_json` / `github_actions_secrets` で値を取得
3. GitHub の Repository Settings > Environments で `gcp-main` Environment を作成 (Azure の `main` と分離)
4. 上記 outputs の値を Variables / Secrets に登録 (`iac/gcp/setup-github-env.ps1` が一発投入用に用意されている)
5. GitHub Actions タブから手動実行 (`workflow_dispatch`)

**SA に付与している権限 (最小権限):**

| SA | 権限 |
|---|---|
| backend deploy SA | `artifactregistry.writer` (バックエンドリポジトリ) / `run.admin` (Cloud Run サービス) / runtime SA への `iam.serviceAccountUser` |
| frontend deploy SA | `storage.objectAdmin` + `storage.legacyBucketReader` (web バケット) / `compute.loadBalancerAdmin` (CDN invalidate) |

### 5.11 Auth0

| リソース | 設定 |
|---|---|
| SPA クライアント (`${app-name}-${environment}-gcp-idp`) | authorization_code, implicit, refresh_token / Web Origin = `local.public_url` |
| リソースサーバー (`${app-name}-${environment}-gcp-audience`) | identifier = `local.public_url`、RS256 |

> `local.public_url` は `lb-domain` 設定時は `https://${lb-domain}`、未設定時は `http://${LB IP}`。

### 5.12 自動起動・停止 (Cloud Scheduler + Cloud Workflows)

| スケジュール | 時刻 (JST) | 対象 | デフォルト |
|---|---|---|---|
| Auto-stop | 毎日 21:00 | Cloud Run scaling → 0 / Cloud SQL `activationPolicy=NEVER` / Bastion VM 停止 | **有効** |
| Auto-start | 土日 7:00 | Bastion 起動 → Cloud SQL `activationPolicy=ALWAYS` (12分待機) → Cloud Run scaling 復帰 | 無効 (paused) |

**手動起動・停止:**

Cloud Console (Workflows) または `gcloud workflows execute` でワークフローを直接起動できる。

| Workflow 名 | 操作 |
|---|---|
| `${app-name}-${environment}-auto-stop` | 停止 |
| `${app-name}-${environment}-auto-start` | 起動 |

### 5.13 ログ分析 (BigQuery sinks)

AWS の Athena (Glue Catalog) に相当。Cloud Logging のログを BigQuery にエクスポートし、`use_partitioned_tables = true` で日付パーティションテーブルを自動作成する。

| Sink 名 | ソース | BigQuery データセット |
|---|---|---|
| `*-lb-logs` | `resource.type = http_load_balancer` | `${app_name}_${environment}_lb_logs` |
| `*-run-logs` | `resource.type = cloud_run_revision` | `${app_name}_${environment}_cloud_run_logs` |
| `*-armor-logs` | `enforcedSecurityPolicy.name = ${edge policy}` | `${app_name}_${environment}_armor_logs` |
| `*-vpc-flow` | `logName = compute.googleapis.com/vpc_flows` | `${app_name}_${environment}_vpc_flow_logs` |

> BigQuery テーブルは sink が初回ログ受信時に自動作成され、スキーマも Cloud Logging が自動推論する。AWS の RegexSerDe / partition projection 相当の設定は不要。

---

## 6. GitHub Actions CI (セキュリティスキャン)

フロントエンド・バックエンドの Pull Request 時に Trivy でセキュリティスキャンを実行する。

| ワークフロー | ファイル | トリガーパス |
|---|---|---|
| CI - Frontend (Trivy scan) | `.github/workflows/ci-frontend.yaml` | `frontend/**` |
| CI - Backend (Trivy scan) | `.github/workflows/ci-backend.yaml` | `backend/**` |

### 5.1 スキャン内容

**フロントエンド:**

| ジョブ | 内容 |
|---|---|
| `trivy-scan` | `frontend/sandbox-frontend` の fs スキャン（依存パッケージ脆弱性 + シークレット検出） |
| `notify-slack` | Slack 通知（CRITICAL/HIGH 脆弱性件数を含む） |

**バックエンド:**

| ジョブ | 内容 |
|---|---|
| `trivy-fs` | `backend/sandbox-backend` の fs スキャン（依存パッケージ脆弱性 + シークレット検出） |
| `trivy-image` | Docker イメージビルド＋スキャン（ECR プッシュなし） |
| `notify-slack` | Slack 通知（fs / image それぞれの CRITICAL/HIGH 件数を含む） |

### 5.2 CVE 抑制 (.trivyignore)

修正不能な CVE を `backend/sandbox-backend/.trivyignore` で管理する。新たに抑制する場合は CVE 番号・理由・追跡 Issue を必ずコメントで記載すること。

| CVE | パッケージ | 理由 | 追跡 |
|---|---|---|---|
| CVE-2026-33671 | picomatch 4.0.3 | yarn.lock は 4.0.4 を指定済み。Docker イメージ内の 4.0.3 の出所が特定できない。本アプリは production で picomatch を使用しない。 | [Issue #59](https://github.com/extra-fe/template-spa-webapp/issues/59) |

### 5.3 手動実行 (workflow_dispatch)

`ALLOWED_DISPATCH_USERS` リポジトリ変数（JSON 配列）に登録したユーザーのみ手動実行可能。

```json
["username1", "username2"]
```

### 5.4 ブランチ保護 (main)

| 設定 | 値 |
|---|---|
| PR 必須 | 有効（承認者 1 名以上） |
| CODEOWNERS レビュー必須 | 有効（`.github/CODEOWNERS` で全ファイルに `@jinka1997` を設定） |
| 古い承認の破棄 | PR 更新時に承認をリセット |

---

## 7. AWS / Azure / GCP リソース対応表

| 機能 | AWS | Azure | GCP |
|---|---|---|---|
| CDN | CloudFront | Front Door Standard | External Application LB + Cloud CDN |
| WAF | AWS WAF v2 (CloudFront scope) | — | Cloud Armor (preconfigured WAF + Adaptive Protection) |
| フロントエンドホスティング | S3 | Storage Account (静的Web) | Cloud Storage (`notFoundPage = index.html`) |
| バックエンド実行環境 | ECS Fargate | App Service (Linux) | Cloud Run (v2) |
| コンテナレジストリ | ECR | ACR | Artifact Registry |
| データベース | Aurora Serverless v2 | PostgreSQL Flexible Server | Cloud SQL for PostgreSQL (Private IP) |
| DB長期バックアップ | AWS Backup (専用Vault) | PostgreSQL Flexible Server組込み (7日保持) | Cloud SQL 自動バックアップ (30件) + PITR (7日) |
| シークレット管理 | SSM Parameter Store | Key Vault | Secret Manager |
| ネットワーク | VPC | VNet | VPC + Serverless VPC Access コネクタ |
| 踏み台 | EC2 Bastion (Session Manager) | Azure Bastion | Compute Engine + IAP TCP forwarding |
| CDN アクセスログ | S3 (v2 CW Logs Delivery) | — | Cloud Logging → BigQuery sink |
| WAFログ | S3 (direct logging) | — | Cloud Logging → BigQuery sink |
| 監視アラーム | CloudWatch Alarms + SNS | — | Cloud Monitoring + Pub/Sub + Email |
| CI/CD | CodePipeline + CodeBuild | GitHub Actions | GitHub Actions |
| 認証基盤 | Auth0 (Terraform管理) | Auth0 (Terraform管理) | Auth0 (Terraform管理) |
| 監視ログ | CloudWatch Logs | Log Analytics Workspace | Cloud Logging |
| CI/CD認証 | CodeStar Connection | OIDC (フェデレーテッド) | OIDC (Workload Identity Federation) |
| 自動起動・停止 | EventBridge Scheduler + Step Functions | (なし) | Cloud Scheduler + Cloud Workflows |
| ログ分析 | Athena (Glue Catalog) | Log Analytics KQL | BigQuery (Logging sink) |
| プライベートサービス接続 | VPC Endpoint (Interface/Gateway) | Private Endpoint | Private Service Access (Service Networking) |

## 8. Terraform 変数

### 8.1 共通変数

| 変数名 | デフォルト | 説明 |
|---|---|---|
| `auth0_domain` | (必須) | Auth0テナントドメイン |
| `auth0_client_id` | (必須) | Auth0 Client ID |
| `auth0_client_secret` | (必須) | Auth0 Client Secret |
| `github-repository-name` | (必須) | GitHubリポジトリ名 |
| `app-name` | `sandbox-aws` / `sandbox` / `sandbox-gcp` | アプリケーション名プレフィックス |
| `environment` | `dev` | 環境名 |
| `frontend-src-root` | `frontend/sandbox-frontend` | フロントエンドのソースパス |
| `backend-src-root` | `backend/sandbox-backend` | バックエンドのソースパス |
| `target-branch` | `main` | CI/CDトリガー対象ブランチ |
| `api-base-path` | `/api/*` | バックエンドAPIのベースパス |
| `health-check-path` | `/health` | ヘルスチェックパス |
| `api-expose-port` | `3000` | コンテナ公開ポート |
| `local-pc-ip-addresses` | `[]` | 接続元IPアドレス（Bastion用） |
| `db-connection-limit` | `5` | Prismaコネクションプール上限（設定指針は 3.5.1 参照） |
| `db-pool-timeout` | `15` | Prismaコネクション空き待ちタイムアウト（秒） |

### 8.2 AWS固有変数

| 変数名 | デフォルト | 説明 |
|---|---|---|
| `codestar-connection-arn` | (必須) | CodeStar接続ARN |
| `vpc_cidr_block` | `172.16.0.0/16` | VPC CIDRブロック |
| `subnet_private1a_cidr_block` | `172.16.2.0/24` | プライベートサブネット1 CIDR |
| `subnet_private1c_cidr_block` | `172.16.3.0/24` | プライベートサブネット2 CIDR |

### 8.3 Azure固有変数

| 変数名 | デフォルト | 説明 |
|---|---|---|
| `azure-subscription-id` | (必須) | AzureサブスクリプションID |
| `location` | `japaneast` | Azureリージョン |
| `public-key-vault-name` | `""` | 公開Key Vault名 |
| `public-key-vault-rg-name` | `""` | 公開Key Vaultリソースグループ名 |
| `public-key-vault-secret` | `""` | 公開Key Vaultシークレット |

### 8.4 GCP固有変数

| 変数名 | デフォルト | 説明 |
|---|---|---|
| `gcp-project-id` | (必須) | GCP プロジェクト ID |
| `gcp-region` | `asia-northeast1` | GCP リージョン (東京) |
| `gcp-zone` | `asia-northeast1-a` | GCP ゾーン (Bastion VM 配置先) |
| `github-owner` | (必須) | GitHub Owner 名 (WIF attribute_condition で使用) |
| `github-environment` | `gcp-main` | GitHub Actions Environment 名 (Azure 側 `main` と分離) |
| `subnet_primary_cidr_block` | `172.16.2.0/24` | プライマリサブネット CIDR |
| `subnet_connector_cidr_block` | `172.16.4.0/28` | Serverless VPC コネクタ専用 /28 サブネット |
| `psa_range_cidr_block` | `172.16.16.0/20` | Private Service Access 用予約 IP レンジ |
| `db-tier` | `db-custom-1-3840` | Cloud SQL マシンタイプ (ENTERPRISE edition 明示) |
| `lb-domain` | `""` | LB 公開ドメイン (Managed SSL + HTTPS リダイレクト用) |
| `alert-notification-emails` | `[]` | Cloud Monitoring アラート通知先 Email |

## 9. デプロイ手順

### 9.1 初回セットアップ

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

# GCP
cd iac/gcp
# 事前に gcloud auth application-default login で ADC を設定
cp terraform.tfvars.example terraform.tfvars  # 変数を編集
terraform init
terraform plan
terraform apply

# WIF / SA 作成後、GitHub Environment "gcp-main" に Variables / Secrets を一括登録
./setup-github-env.ps1
```

### 9.2 アプリケーションデプロイ

**AWS:**
- `main` ブランチへのpushでCodePipelineが自動トリガー
- バックエンド: `backend/**` のファイル変更でトリガー
- フロントエンド: `frontend/**` のファイル変更でトリガー

**Azure:**
- GitHub Actionsワークフローを手動実行 (`workflow_dispatch`)
- Key Vaultから動的に設定値を取得

**GCP:**
- GitHub Actions ワークフローを手動実行 (`workflow_dispatch`) で Environment = `gcp-main` を選択
- OIDC (Workload Identity Federation) でデプロイ SA に impersonation
- バックエンド: `deploy-backend-gcp.yaml` → Artifact Registry push → `gcloud run services update`
- フロントエンド: `deploy-frontend-gcp.yaml` → GCS rsync → URL マップ invalidate

## 10. セキュリティ設計

| セキュリティ施策 | AWS | Azure | GCP |
|---|---|---|---|
| DB非公開 | プライベートサブネット | VNet統合 + パブリックアクセス無効 | Private IP (PSA) + `ipv4_enabled = false` |
| シークレット管理 | SSM Parameter Store (SecureString) | Key Vault | Secret Manager (user_managed replication) |
| CDNオリジン保護 | OAC (S3), VPC Origin (ALB) | IP制限 (Front Door Backend) | Cloud Run `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` + GCS public_access_prevention |
| CI/CD認証 | CodeStar Connection | OIDC (フェデレーテッド資格情報) | OIDC (Workload Identity Federation + Environment 限定 principalSet) |
| コンテナレジストリ | プライベートECR | Managed Identity (AcrPull) | Artifact Registry (Cloud Run ランタイム SA に reader 付与) |
| 通信暗号化 | HTTPS リダイレクト | HTTPS (Front Door) | HTTPS リダイレクト (`lb-domain` 設定時 Managed SSL) |
| ストレージ暗号化 | Aurora暗号化有効 | - | Cloud SQL (デフォルトで保存時暗号化、GMEK) |
| バックアップ暗号化 | AWS Backup Vault (`aws/backup` KMSキー) | PostgreSQLサービス組込み | Cloud SQL 自動バックアップ (Google マネージド暗号化) |
| アクセス制御 | セキュリティグループ | NSG + サブネットデリゲーション | VPC Firewall (target tags + IAP source range) |
| 最小権限ルール | ALB/ECS/DB/Bastion/SSM endpoint の egress を用途別ポート・宛先に限定（DB egress なし） | — | Bastion egress を 443 / 5432 + PSA range に限定、 SSH は IAP `35.235.240.0/20` のみ許可 |
| IAM 最小権限 | CodePipeline ECS権限を特定タスク定義・クラスタ ARN に限定 | — | Cloud Build SA に `artifactregistry.writer` / `clouddeploy.releaser` のみ付与、deploy 用 SA を分離 |
| WAF | AWS WAF v2 (managed rule groups) | — | Cloud Armor (preconfigured WAF + Adaptive Protection) |
| 踏み台アクセス | EC2 + SSM Session Manager (SSH キー不要) | Azure Bastion | IAP TCP forwarding (gcloud `--tunnel-through-iap`) — public IP なし、SSH キー不要 |
