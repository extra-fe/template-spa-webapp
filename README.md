# template-spa-webapp

技術書典18・19で出した本から参照しているコードを保存しているリポジトリです。

競馬レース管理をテーマにしたSPAアプリケーションを、**AWS** と **Azure** の両クラウドにデプロイするテンプレートプロジェクトです。

## 書籍について

| 回 | 書籍名 | タグ |
|---|---|---|
| 技術書典18 | **ローカル環境を作ってAWSとAzureにデプロイ** | [`技術書典18`](../../releases/tag/技術書典18) |
| 技術書典19 | **ローカル環境を作ってAWSとAzureにデプロイ2 RDB編 OpenTelemetryもあるよ** | [`技術書典19`](../../releases/tag/技術書典19) |

各書籍執筆時点のコードはタグから参照できます。

## アーキテクチャ概要

```
User ── HTTPS ──> CloudFront (+ WAF v2) / Front Door (CDN)
                      │
                      ├── /*      ──> S3 / Storage Account (React SPA)
                      │
                      └── /api/*  ──> ALB + ECS Fargate / App Service (NestJS API)
                                          │
                                          └──> Aurora Serverless / PostgreSQL Flexible Server
```

## 技術スタック

| レイヤー | 技術 |
|---|---|
| Frontend | React 19 / TypeScript / Vite / Auth0 |
| Backend | NestJS 11 / Prisma / PostgreSQL / OpenTelemetry |
| IaC | Terraform 1.13 |
| CI/CD (AWS) | CodePipeline + CodeBuild |
| CI/CD (Azure) | GitHub Actions (OIDC) |
| セキュリティスキャン | GitHub Actions (Trivy) |
| 認証 | Auth0 (JWT / RS256) |

## ディレクトリ構成

```
.
├── frontend/sandbox-frontend/   # React SPA (Vite)
├── backend/sandbox-backend/     # NestJS API (Docker)
├── iac/
│   ├── aws/                     # AWS Terraform
│   └── azure/                   # Azure Terraform
├── docs/                        # 仕様書・構成図
│   ├── frontend-spec.md
│   ├── backend-spec.md
│   ├── iac-spec.md
│   └── diagrams/                # インフラ構成図 (Draw.io SVG)
├── appendix/                    # 正誤表・補足資料
└── .github/
    ├── CODEOWNERS               # レビュー必須設定
    └── workflows/               # GitHub Actions CI (Trivy scan, Azure deploy)
```

## AWS / Azure リソース対応表

| 機能 | AWS | Azure |
|---|---|---|
| CDN | CloudFront | Front Door Standard |
| フロントエンド | S3 | Storage Account (静的Web) |
| バックエンド | ECS Fargate | App Service (Linux B1) |
| コンテナレジストリ | ECR | ACR |
| データベース | Aurora Serverless v2 (PostgreSQL 16) | PostgreSQL Flexible Server (v16) |
| DB長期バックアップ | AWS Backup (日次・30日保持) | PostgreSQL Flexible Server組込み (7日保持) |
| シークレット管理 | SSM Parameter Store | Key Vault |
| ネットワーク | VPC (172.16.0.0/16) | VNet (10.0.0.0/24) |
| WAF | AWS WAF v2 (CloudFront scope, マネージドルール3種) | — |
| VPCフローログ | S3 + `aws_flow_log` | — |
| ALBアクセスログ | S3 | — |
| CloudFrontアクセスログ | S3 (v2 CW Logs Delivery, JSON) | — |
| WAFログ | S3 (direct logging, JSON) | — |
| ログ分析 | Athena + Glue Data Catalog（partition projection）VPC/ALB/CF/WAF | — |
| 監視アラーム | CloudWatch Alarms + SNS | — |
| 自動起動・停止 | EventBridge Scheduler + Step Functions | — |
| CI/CD | CodePipeline (自動トリガー) | GitHub Actions (手動トリガー) |

## セットアップ

### ローカル開発

```bash
# Backend
cd backend/sandbox-backend
yarn install
yarn start:dev          # http://localhost:3000

# Frontend
cd frontend/sandbox-frontend
yarn install
yarn dev                # http://localhost:5173
```

バックエンドは `AUTH_ENABLED=false` でモック認証モードで起動できます。

### インフラデプロイ

```bash
# AWS
cd iac/aws
terraform init && terraform apply

# Azure
cd iac/azure
terraform init && terraform apply
```

詳細は [IaC仕様書](./docs/iac-spec.md) を参照してください。

### DB接続プール設定の指針 (AWS)

`iac/aws/variables.tf` の以下の変数でPrismaのコネクションプールを調整します。

| 変数 | デフォルト | 説明 |
|---|---|---|
| `db-connection-limit` | `5` | Prismaが1プロセスで保持するコネクション数の上限 |
| `db-pool-timeout` | `15` | コネクション空き待ちのタイムアウト（秒） |

**`db-connection-limit` の決め方:**

Aurora Serverless v2 の最大コネクション数はACUに比例します。

| インスタンス / ACU | メモリ | 最大コネクション数（概算） |
|---|---|---|
| Serverless v2 0.5 ACU | 1 GiB | 約 45 |
| Serverless v2 1.0 ACU | 2 GiB | 約 90 |
| Serverless v2 2.0 ACU | 4 GiB | 約 180 |
| db.t3.medium | 4 GiB | 約 450 |
| db.m5.large | 8 GiB | 約 900 |
| db.m5.xlarge | 16 GiB | 約 1,800 |
| db.m5.2xlarge | 32 GiB | 約 3,600 |

> 正確な値は `LEAST({DBInstanceClassMemory / 9531392}, 5000)` で計算されます。

以下の条件を満たす値を設定してください。

```
ECSタスク最大数 × db-connection-limit ≦ Aurora最大コネクション数 × 0.8 (安全マージン)
```

例: ACU最大 1.0（最大コネクション90）、ECSタスク最大10台の場合
```
10 × db-connection-limit ≦ 90 × 0.8 = 72
→ db-connection-limit ≦ 7  （余裕を見て 5 程度を推奨）
```

### ログ分析 / Athena (AWS)

VPCフローログ・ALBアクセスログ・CloudFrontアクセスログ・WAFログをS3へ記録し、Athenaを使ってSQLでクエリできます。partition projection によりパーティションの手動追加は不要です。

クエリ手順・サンプルSQLは [運用・調査コマンドリファレンス](./docs/operations.md#athena---ログ分析クエリ) を参照してください。

### Auroraバックアップ (AWS Backup)

Aurora Serverless v2の自動バックアップ（最大35日）とは別系統で、AWS Backupによる長期バックアップを設定しています。

| 項目 | 値 |
|---|---|
| Backup Vault | `{app-name}-{environment}-aurora-vault`（専用Vault・`aws/backup` KMSキー） |
| スケジュール | 日次 02:00 JST |
| 保持期間 | 30日 |
| クロスリージョンコピー | 無効 |

> auto-stop (13:00 JST) によりバックアップ実行時刻にはAuroraが停止していますが、停止中クラスタもスナップショット取得は可能です。

バックアップ一覧・復元手順は [運用・調査コマンド](./docs/operations.md#aurora-aws-backup) を参照してください。

### 監視アラーム (AWS)

CloudWatch Alarms + SNS で ECS・Aurora の異常を検知します。アラーム発火時は SNS トピック `{app-name}-{environment}-alarms` に通知されます。

> SNS サブスクリプション（メール・Slack等）は Terraform 管理外です。デプロイ後に AWS コンソールから手動で登録してください。

| アラーム名 | 対象 | 閾値 | 評価 |
|---|---|---|---|
| `ecs-cpu-high` | ECS CPU使用率 | > 80% | 2回連続 |
| `ecs-memory-high` | ECS メモリ使用率 | > 80% | 2回連続 |
| `aurora-connections-high` | Auroraコネクション数 | > 70 | 2回連続 |
| `aurora-cpu-high` | Aurora CPU使用率 | > 80% | 2回連続 |
| `aurora-acu-high` | Aurora ACU使用率 | > 80% | 2回連続 |
| `aurora-freeable-memory-low` | Aurora 空きメモリ | < 200 MiB | 2回連続 |
| `aurora-free-local-storage-low` | Aurora ローカルストレージ空き | < 512 MiB | 2回連続 |
| `aurora-volume-bytes-high` | Aurora ボリュームサイズ | > 100 GiB | 2回連続 |

### 自動起動・停止 (AWS)

開発コスト削減のため、EventBridge Scheduler + Step Functions でリソースを自動制御しています。

| スケジュール | 時刻（JST） | 対象 | デフォルト |
|---|---|---|---|
| Auto-stop | 毎日 13:00 | ECS（タスク数→0）→ Aurora 停止 → Bastion 停止 | **有効** |
| Auto-start | 土日 5:00 | Bastion 起動 → Aurora 起動（12分待機）→ ECS（タスク数→1） | 無効 |

> Auto-start はデフォルト無効です。平日も自動起動したい場合は AWS コンソール（EventBridge Scheduler）またはTerraformの `state` を `"ENABLED"` に変更してください。

**手動で起動・停止する場合**

Step Functions コンソールから対象のステートマシンを選択し「実行を開始」してください。

| ステートマシン名 | 操作 |
|---|---|
| `exec-auto-stop-{app-name}-{environment}` | 停止 |
| `exec-auto-start-{app-name}-{environment}` | 起動 |

#### ECSコンテナログ

ECSアプリコンテナのログ（FireLens / Fluent Bit 経由）をS3へ記録し、Athenaでクエリできます。ヘルスチェックのログは除外されています。

クエリ手順・サンプルSQLは [運用・調査コマンドリファレンス](./docs/operations.md#athena---ログ分析クエリ) を参照してください。

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [Frontend仕様書](./docs/frontend-spec.md) | ルーティング、Auth0認証、画面仕様、API通信 |
| [Backend仕様書](./docs/backend-spec.md) | APIエンドポイント、DBスキーマ、JWT認証、OpenTelemetry |
| [IaC仕様書](./docs/iac-spec.md) | AWS/Azure リソース定義、CI/CD、セキュリティ設計、Trivy スキャン設定 |
| [AWS構成図](./docs/diagrams/aws-architecture.drawio.svg) | AWS インフラ構成図 (Draw.io SVG) |
| [Azure構成図](./docs/diagrams/azure-architecture.drawio.svg) | Azure インフラ構成図 (Draw.io SVG) |
| [CI/CDパイプライン図](./docs/diagrams/cicd-pipeline.drawio.svg) | AWS/Azure CI/CD 比較図 (Draw.io SVG) |
| [運用・調査コマンド](./docs/operations.md) | CloudWatch Logs・Athena・ECSヘルスチェック等の調査用コマンド集 |

## 正誤表

書籍の正誤表は [こちら](./appendix/errata.md) をご確認ください。

| No | 内容 | セクション |
|---|---|---|
| 1 | Auth0 API呼び出し用のパーミッション不足 | 1.2.10 IdP(Auth0) |
| 2 | CloudFront VPCオリジン取得用のfilter条件不足 | 2.2.5 CloudFront VPCオリジン |

## コマンドリファレンス

MFA認証・リソース削除・調査コマンド等は [運用・調査コマンドリファレンス](./docs/operations.md) を参照してください。
