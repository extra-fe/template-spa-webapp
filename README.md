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
                      └── /api/*  ──> ALB + ECS Fargate / Container Apps (NestJS API)
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
| バックエンド | ECS Fargate | Container Apps (Workload Profiles / Consumption, VNet 統合) |
| コンテナレジストリ | ECR | ACR |
| データベース | Aurora Serverless v2 (PostgreSQL 16) | PostgreSQL Flexible Server (v16) |
| DB長期バックアップ | AWS Backup (日次・30日保持) | PostgreSQL Flexible Server組込み (7日保持) |
| シークレット管理 | SSM Parameter Store | Key Vault (network_acls 有効、 Container App は内蔵 secret store) |
| ネットワーク | VPC (172.16.0.0/16) | VNet (10.0.0.0/24) |
| WAF | AWS WAF v2 (CloudFront scope, マネージドルール3種) | — (Front Door Standard は WAF 未対応、 Premium への upgrade が必要) |
| VPCフローログ | S3 + `aws_flow_log` | VNet Flow Logs + Traffic Analytics (Storage + Log Analytics) |
| ALBアクセスログ | S3 | — (Front Door が CloudFront/ALB を兼ねる) |
| CloudFrontアクセスログ | S3 (v2 CW Logs Delivery, JSON) | Front Door 診断ログ (Storage + Log Analytics, Dedicated テーブル) |
| WAFログ | S3 (direct logging, JSON) | — (WAF 自体が未配置のため) |
| ログ分析 | Athena + Glue Data Catalog（partition projection）VPC/ALB/CF/WAF | Log Analytics + KQL (saved searches: VNet Flow / Front Door / Container App) |
| 監視アラーム | CloudWatch Alarms + SNS | Azure Monitor Metric Alerts + Action Group (Container App / PostgreSQL) |
| 自動起動・停止 | EventBridge Scheduler + Step Functions | Azure Automation Account + PowerShell Runbook + Schedule |
| CI/CD | CodePipeline (自動トリガー) | GitHub Actions (OIDC + GitHub Environments, 手動トリガー) |

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

バックエンドは `.env` で `AUTH_ENABLED=false` を設定するとモック認証モードで起動できます（Auth0 不要）。フロントエンドも `.env` で `VITE_AUTH_ENABLED=false` を設定すると `/races` 等の保護ルートで Auth0 リダイレクトをスキップし、API 呼び出しから `Authorization` ヘッダを省きます。

Windows / PowerShell で DB 起動・マイグレーション・backend/frontend の起動を一括で行う `dev-up.ps1` を用意しています。詳細は [ローカル開発ガイド](./docs/local-dev.md) を参照してください。

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

#### Azure: GitHub Actions のセットアップ (初回のみ)

Azure 側は **Key Vault に `network_acls` を有効化している**ため、 GitHub Actions ワークフローが Key Vault から secret を直接読み出す方式は使えません。 代わりに **GitHub Environments の Variables/Secrets** に値を登録します。

```powershell
cd iac/azure

# 1. GitHub UI で `main` Environment を作成
#    Settings → Environments → New environment → "main"

# 2. terraform output から値を取得して main Environment に一括登録
$vars = terraform output -json github_actions_variables | ConvertFrom-Json
$vars.PSObject.Properties | ForEach-Object {
  gh variable set $_.Name --env main --body $_.Value
}
$secrets = terraform output -json github_actions_secrets | ConvertFrom-Json
$secrets.PSObject.Properties | ForEach-Object {
  gh secret set $_.Name --env main --body $_.Value
}

# 3. OIDC 用 secrets (AZURE_CLIENT_ID / TENANT_ID / SUBSCRIPTION_ID) は
#    repository-level secrets に別途登録 (Key Vault の github-AZURE-* secret から取得可)

# 4. ワークフロー実行
gh workflow run deploy-backend-azure.yaml --ref main --field environment=main
gh workflow run deploy-frontend-azure.yaml --ref main --field environment=main
```

別環境 (staging/prod) を追加する場合は、 `iac/azure/service-principal.tf` の federated credential を for_each で増やし、 `deploy-*-azure.yaml` の `inputs.environment.options` にも追加してください。

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

### ログ分析 (Azure)

VNet Flow Logs (Traffic Analytics) と Front Door 診断ログを Log Analytics Workspace に集約し、 KQL クエリで分析します (AWS の Athena 相当)。

代表的なクエリは `iac/azure/log_analytics_queries.tf` に `azurerm_log_analytics_saved_search` として登録されており、 Azure Portal の Log Analytics → Saved searches から実行できます:

- VNet Flow: 宛先別バイト数 TOP10 / 拒否フロー一覧
- Front Door: ステータスコード分布 / 4xx・5xx エラーパス TOP20
- Container App: コンソール ERROR 抽出 / システムイベント (リビジョン起動失敗等)

ログは合わせて Storage Account (`*-logs`) にも長期保管 (Hot → Cool@31d → Archive@365d ライフサイクル) されます。

### 監視アラーム (Azure)

Azure Monitor Metric Alerts + Action Group で Container App と PostgreSQL Flexible Server の異常を検知します:

- **Container App**: `UsageNanoCores` / `WorkingSetBytes` / `RestartCount` (クラッシュループ検知)
- **PostgreSQL**: `cpu_percent` / `memory_percent` / `storage_percent` / `active_connections`

通知先 (メール/Slack等) は Terraform 管理外のため、 デプロイ後に Action Group `<app>-<env>-alarms` に手動登録してください。

### 自動起動・停止 (Azure)

Azure Automation Account + PowerShell Runbook + Schedule で PostgreSQL Flexible Server と Bastion VM を毎日 21:00 JST に自動停止します (`auto_start` は既定で無効、 `auto-start-enabled = true` で土日 05:00 起動)。

Container App は `min_replicas = 0` で **scale-to-zero 動作**するため、 アイドル時は自動でゼロ課金になり、 Runbook での明示停止は不要です。

詳細は [iac/azure/start-stop-resources.tf](./iac/azure/start-stop-resources.tf) を参照してください。

## セキュリティ強化 (Web脆弱性診断 事前対応)

第三者Web脆弱性診断を見据えたハードニングを適用済みです。適用済み項目・意図的に未適用とした項目・診断実施時の注意事項は [セキュリティ強化ガイド](./docs/security-hardening.md) を参照してください。

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
| [セキュリティ強化ガイド](./docs/security-hardening.md) | Web脆弱性診断事前対応の適用済み項目・未適用項目・診断時の注意事項 |
| [ローカル開発ガイド](./docs/local-dev.md) | Windows / PowerShell 用 `dev-up.ps1` の使い方・前提・スクリプト動作内容 |

## 正誤表

書籍の正誤表は [こちら](./appendix/errata.md) をご確認ください。

| No | 内容 | セクション |
|---|---|---|
| 1 | Auth0 API呼び出し用のパーミッション不足 | 1.2.10 IdP(Auth0) |
| 2 | CloudFront VPCオリジン取得用のfilter条件不足 | 2.2.5 CloudFront VPCオリジン |

## コマンドリファレンス

MFA認証・リソース削除・調査コマンド等は [運用・調査コマンドリファレンス](./docs/operations.md) を参照してください。
