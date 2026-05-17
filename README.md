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
User ── HTTPS ──> CloudFront / Front Door (CDN)
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
└── .github/workflows/           # GitHub Actions (Azure用)
```

## AWS / Azure リソース対応表

| 機能 | AWS | Azure |
|---|---|---|
| CDN | CloudFront | Front Door Standard |
| フロントエンド | S3 | Storage Account (静的Web) |
| バックエンド | ECS Fargate | App Service (Linux B1) |
| コンテナレジストリ | ECR | ACR |
| データベース | Aurora Serverless v2 (PostgreSQL 16) | PostgreSQL Flexible Server (v16) |
| シークレット管理 | SSM Parameter Store | Key Vault |
| ネットワーク | VPC (172.16.0.0/16) | VNet (10.0.0.0/24) |
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

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [Frontend仕様書](./docs/frontend-spec.md) | ルーティング、Auth0認証、画面仕様、API通信 |
| [Backend仕様書](./docs/backend-spec.md) | APIエンドポイント、DBスキーマ、JWT認証、OpenTelemetry |
| [IaC仕様書](./docs/iac-spec.md) | AWS/Azure リソース定義、CI/CD、セキュリティ設計 |
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
