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
| IaC | Terraform 1.13.5 |
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
cp .env.example .env    # 実値を編集
yarn install
yarn start:dev          # http://localhost:3000

# Frontend
cd frontend/sandbox-frontend
cp .env.example .env    # 実値を編集
yarn install
yarn dev                # http://localhost:5173
```

バックエンドは `.env` で `AUTH_ENABLED=false` を設定するとモック認証モードで起動できます（Auth0 不要）。

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

### ログ分析 / Athena (AWS)

VPCフローログ・ALBアクセスログ・CloudFrontアクセスログ・WAFログをS3へ記録し、Athenaを使ってSQLでクエリできます。partition projection によりパーティションの手動追加は不要です。

クエリ手順・サンプルSQLは [運用・調査コマンドリファレンス](./docs/operations.md#athena---ログ分析クエリ) を参照してください。

### Auroraバックアップ (AWS Backup)

Aurora Serverless v2の自動バックアップ（最大35日）とは別系統で、AWS Backupによる日次・30日保持の長期バックアップを設定しています。

設定詳細は [IaC仕様書 3.5.2](./docs/iac-spec.md#352-バックアップ-aws-backup)、バックアップ一覧・復元手順は [運用・調査コマンド](./docs/operations.md#aurora-aws-backup) を参照してください。

### 監視アラーム (AWS)

CloudWatch Alarms + SNS で ECS・Aurora の異常を検知します。SNS サブスクリプション（メール・Slack等）は Terraform 管理外のため、デプロイ後に手動登録が必要です。

詳細は [IaC仕様書 3.10](./docs/iac-spec.md#310-監視アラーム-cloudwatch-alarms) を参照してください。

### 自動起動・停止 (AWS)

開発コスト削減のため、EventBridge Scheduler + Step Functions で毎日 13:00 に自動停止します（Auto-start はデフォルト無効）。

詳細・手動操作手順は [IaC仕様書 3.13](./docs/iac-spec.md#313-自動起動停止-eventbridge-scheduler--step-functions) を参照してください。

## セキュリティ強化 (Web脆弱性診断 事前対応)

第三者Web脆弱性診断を見据えた一般的なハードニングを適用済みです。本セクションでは **適用済み項目** と **テンプレートとして意図的に未適用とした項目** を整理しています。プロジェクトの要件に応じて未適用項目を取捨選択してください。

### 適用済み項目

| 領域 | 内容 |
|---|---|
| CloudFront | レスポンスヘッダポリシー (HSTS / CSP / X-Frame-Options / X-Content-Type-Options / Referrer-Policy / Permissions-Policy) / `/api/*` を `https-only` 化 |
| WAF | レートベースルール (`/api/*` で 5分2000req/IP, Block) / AnonymousIpList マネージドルール (`HostingProviderIPList` は Count 化) |
| ALB | `drop_invalid_header_fields = true` (HTTP リクエストスマグリング対策) |
| S3 | 全バケットに SSE-S3 (AES256) 既定暗号化を明示適用 |
| NestJS | Helmet / グローバル ValidationPipe (`whitelist` + `forbidNonWhitelisted` + `transform`) / グローバル例外フィルタ (本番でスタック非露出) |

### 意図的に未適用とした項目

テンプレートのシンプルさと診断要件のバランスから、以下は **未適用** としています。

#### 1. アプリケーション層レート制限 (`@nestjs/throttler`)

- **未適用の理由**: WAF v2 のレートベースルール (`/api/*` で 2000req/5min/IP) で代替済み。`@nestjs/throttler` のデフォルトメモリストアは ECS マルチタスク構成では共有されず、Redis 等の外部ストア導入が必要になり構成が肥大化する。
- **適用を検討すべきケース**:
  - ログインや OTP 等の特定エンドポイントに細粒度なスロットリングを掛けたい
  - WAF を使わない環境にデプロイする (Azure App Service 等)
  - 認証済みユーザー単位 (JWT `sub`) でレート制限したい

#### 2. CloudFront `/api/*` の HTTP メソッド絞り込み

- **未適用の理由**: CloudFront の `allowed_methods` は `["GET","HEAD"]` / `["GET","HEAD","OPTIONS"]` / 全7メソッドの3パターンしか選択できず、`POST` を使う本テンプレートでは全許可セット以外を選べない。NestJS は未定義メソッド (`PUT`/`PATCH`/`DELETE` 等) へ 404 を返すため実害なし。
- **適用を検討すべきケース**: 診断ツールが「unused HTTP methods allowed」を指摘した場合、WAF カスタムルールで `/api/*` 配下の未使用メソッドを Block する (実装するとアプリ側で新メソッド追加時に WAF ルール更新が必要)。

#### 3. CloudFront カスタムドメイン + ACM (TLSv1.2 強制)

- **未適用の理由**: デフォルト証明書 (`*.cloudfront.net`) 利用時は `minimum_protocol_version` を `TLSv1.2_*` に上げても実質無視される (AWS の仕様)。カスタムドメインと ACM 証明書を導入して初めて TLSv1.2/1.3 強制が有効になる。
- **適用を検討すべきケース**: 本番運用でカスタムドメインを使う場合。同時に HSTS の `preload` 有効化と HSTS Preload List 申請も行うと診断スコアがさらに改善。

#### 4. S3 SSE-KMS (顧客管理キー)

- **未適用の理由**: SSE-S3 (AES256) で診断要件は満たせる。SSE-KMS は KMS 使用料 + 各サービスへの KMS 権限付与が必要で、テンプレートの初期構成としては過剰。
- **適用を検討すべきケース**: 監査要件で「鍵の使用ログ取得」「鍵ローテーションの管理者制御」が必要な場合。

### 診断実施時の運用上の注意

- **WAF レート制限と診断ツールの衝突**: 第三者診断ツールは大量リクエストを送るため `/api/*` のレートベースルール (2000req/5min/IP) に引っかかる可能性が高い。診断ベンダのソース IP 帯が判明したら、`aws_wafv2_ip_set` + 高優先度 (priority < 40) の allow ルールを一時追加する。
- **AnonymousIpList の HostingProviderIPList**: 上記の通り Count 化してあるため、クラウド由来の診断トラフィックはブロックされない (ログには記録される)。
- **WAF ログでの結果確認**: CSP 違反やレート制限ヒットは Athena (`waf_logs` テーブル) で集計可能。

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
