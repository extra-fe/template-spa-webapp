# template-spa-webapp

技術書典18・19で出した本から参照しているコードを保存しているリポジトリです。

競馬レース管理をテーマにしたSPAアプリケーションを、**AWS** / **Azure** / **GCP** の 3 クラウドにデプロイするテンプレートプロジェクトです。

## 書籍について

| 回 | 書籍名 | タグ |
|---|---|---|
| 技術書典18 | **ローカル環境を作ってAWSとAzureにデプロイ** | [`技術書典18`](../../releases/tag/技術書典18) |
| 技術書典19 | **ローカル環境を作ってAWSとAzureにデプロイ2 RDB編 OpenTelemetryもあるよ** | [`技術書典19`](../../releases/tag/技術書典19) |

各書籍執筆時点のコードはタグから参照できます。

## アーキテクチャ概要

```
User ── HTTPS ──> CloudFront (+ WAF v2) / Front Door / External Application LB (+ Cloud Armor)
                      │
                      ├── /*      ──> S3 / Storage Account / Cloud Storage (React SPA)
                      │
                      └── /api/*  ──> ALB + ECS Fargate / Container Apps / Cloud Run (NestJS API)
                                          │
                                          └──> Aurora Serverless / PostgreSQL Flexible Server / Cloud SQL for PostgreSQL
```

## 技術スタック

| レイヤー | 技術 |
|---|---|
| Frontend | React 19 / TypeScript / Vite / Auth0 |
| Backend | NestJS 11 / Prisma / PostgreSQL / OpenTelemetry |
| IaC | Terraform 1.13.5 |
| CI/CD (AWS) | CodePipeline + CodeBuild |
| CI/CD (Azure) | GitHub Actions (OIDC) |
| CI/CD (GCP) | GitHub Actions (OIDC / Workload Identity Federation) |
| セキュリティスキャン | GitHub Actions (Trivy) |
| 認証 | Auth0 (JWT / RS256) |

## ディレクトリ構成

```
.
├── frontend/sandbox-frontend/   # React SPA (Vite)
├── backend/sandbox-backend/     # NestJS API (Docker)
├── iac/
│   ├── aws/                     # AWS Terraform
│   ├── azure/                   # Azure Terraform
│   └── gcp/                     # GCP Terraform
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

## AWS / Azure / GCP リソース対応表

| 機能 | AWS | Azure | GCP |
|---|---|---|---|
| CDN | CloudFront | Front Door Standard | External Application LB + Cloud CDN |
| フロントエンド | S3 | Storage Account (静的Web) | Cloud Storage (`notFoundPage = index.html`) |
| バックエンド | ECS Fargate | Container Apps (Workload Profiles / Consumption, VNet 統合) | Cloud Run v2 (Serverless NEG, ingress = INTERNAL_LOAD_BALANCER) |
| コンテナレジストリ | ECR | ACR | Artifact Registry |
| データベース | Aurora Serverless v2 (PostgreSQL 16) | PostgreSQL Flexible Server (v16) | Cloud SQL for PostgreSQL 16 (Private IP / PSA) |
| DB長期バックアップ | AWS Backup (日次・30日保持) | PostgreSQL Flexible Server組込み (7日保持) | Cloud SQL 自動バックアップ (30件保持) + PITR (7日) |
| シークレット管理 | SSM Parameter Store | Key Vault (network_acls 有効、 Container App は内蔵 secret store) | Secret Manager (user_managed replication) |
| ネットワーク | VPC (172.16.0.0/16) | VNet (10.0.0.0/24) | VPC + Serverless VPC Access コネクタ (172.16.0.0/16) |
| WAF | AWS WAF v2 (CloudFront scope, マネージドルール3種) | — (Front Door Standard は WAF 未対応、 Premium 化で利用可能 → [SKU 選択について](./docs/azure-frontdoor-sku.md)) | Cloud Armor (preconfigured WAF + Adaptive Protection + レート制限) |
| VPCフローログ | S3 + `aws_flow_log` | VNet Flow Logs + Traffic Analytics (Storage + Log Analytics) | VPC Flow Logs → Cloud Logging |
| ALBアクセスログ | S3 | — (Front Door が CloudFront/ALB を兼ねる) | — (External LB が CDN/ALB を兼ねる) |
| CDN アクセスログ | S3 (v2 CW Logs Delivery, JSON) | Front Door 診断ログ (Storage + Log Analytics, Dedicated テーブル) | LB request logs → Cloud Logging → BigQuery sink |
| WAFログ | S3 (direct logging, JSON) | — (WAF 自体が未配置のため) | Cloud Armor ログ → Cloud Logging → BigQuery sink |
| ログ分析 | Athena + Glue Data Catalog（partition projection）VPC/ALB/CF/WAF | Log Analytics + KQL (saved searches: VNet Flow / Front Door / Container App) | BigQuery (Logging sink, use_partitioned_tables): LB / Cloud Run / Armor / VPC Flow |
| 監視アラーム | CloudWatch Alarms + SNS | Azure Monitor Metric Alerts + Action Group (Container App / PostgreSQL) | Cloud Monitoring Alert Policy + Email チャネル (Cloud Run / Cloud SQL) |
| 自動起動・停止 | EventBridge Scheduler + Step Functions | Azure Automation Account + PowerShell Runbook + Schedule | Cloud Scheduler + Cloud Workflows |
| 踏み台 | EC2 + SSM Session Manager | Linux VM + SSH (Key Vault 公開鍵) | Compute Engine + IAP TCP forwarding |
| CI/CD | CodePipeline (自動トリガー) | GitHub Actions (OIDC + GitHub Environments, 手動トリガー) | GitHub Actions (OIDC / Workload Identity Federation, 手動トリガー) |
| HTTPS | CloudFront 既定 `*.cloudfront.net` | Front Door 既定 `*.azurefd.net` | Google Managed SSL (`lb-domain` 設定時、 ドメイン必須) |

## エッジセキュリティ (CDN / WAF) の構成

3 クラウドとも「CDN・エッジ層 → API バックエンド」という階層は共通ですが、 WAF の配置は採用 SKU の制約で違いが出ます。

### 現状

| クラウド | 経路 | WAF 配置 |
|---|---|---|
| AWS | CloudFront → ALB → ECS Fargate | ✅ AWS WAF v2 を **CloudFront (scope=CLOUDFRONT)** にアタッチ ([iac/aws/waf.tf](./iac/aws/waf.tf)) |
| GCP | External Application LB → Cloud Run | ✅ Cloud Armor を **API backend service** にアタッチ ([iac/gcp/cloud_armor.tf](./iac/gcp/cloud_armor.tf), [iac/gcp/load_balancer.tf](./iac/gcp/load_balancer.tf)) |
| Azure | Front Door **Standard** → Container Apps | ❌ Front Door Standard は WAF 非対応 (Premium 専用機能) |

ルール内容は AWS / GCP とも概ね同等で、 OWASP 系マネージドルール群 (SQLi / XSS / LFI / RCE / Protocol attack / Scanner detection) + `/api/*` に対する 5 分 / IP / 2000 リクエストのレート制限を実装しています。

GCP の Cloud Armor は Cloud LB のフロントエンドではなく **API の backend service にアタッチ**しているため、 静的アセット側 (Cloud Storage) には WAF が掛かりません (攻撃面が小さいため意図的に省略)。

### Azure を Front Door Premium に上げた場合

| 観点 | Standard (現状) | Premium (移行後) |
|---|---|---|
| 経路 | Front Door → Container Apps (ingress: public) | Front Door → **Private Link** → Container Apps (ingress: internal) を選択可。 公開接点を Front Door に集約できる |
| セキュリティ | WAF なし。 アプリ層で `X-Azure-FDID` ヘッダ検証する想定 (本テンプレ未実装) | **WAF (Microsoft_DefaultRuleSet + Microsoft_BotManagerRuleSet)** を Front Door にアタッチして AWS / GCP と並ぶエッジ防御レベル |
| コスト (Japan East 月額目安) | 約 $35 | **約 $330** (約 10 倍) |

dev/sandbox 用途では Standard、本番リリース時に Premium へ切り替える運用を想定しています。 upgrade 手順 (`sku_name` 変更 + `azurerm_cdn_frontdoor_firewall_policy` / `azurerm_cdn_frontdoor_security_policy` 追加) と Standard 採用理由の詳細は [Front Door の SKU 選択について (Azure)](./docs/azure-frontdoor-sku.md) を参照してください。

## フロントエンドデプロイ時のキャッシュ戦略

Vite ビルドが生成する `dist/` は 2 種類のファイルに分かれ、 それぞれ異なる `Cache-Control` でアップロードします。

| ファイル種別 | 例 | Cache-Control |
|---|---|---|
| ハッシュ付きアセット | `assets/index-Abc123.js` / `assets/main-Xyz789.css` | `public, max-age=31536000, immutable` (1 年) |
| エントリポイント | `index.html` | `no-store, no-cache` |

`index.html` は新しいハッシュ付きアセット URL を指す唯一のファイルです。 キャッシュされて古い `index.html` が返ると、 中で参照されているアセット URL (`assets/index-<oldhash>.js`) は新デプロイ後の Storage には既に存在しないため **404 (白画面)** になります。 CDN 側のパージはユーザブラウザに残ったキャッシュには無力なため、 アップロード時の `Cache-Control` 付与が必須です。

3 クラウドとも同じ戦略で、 デプロイ時に「アセット長期キャッシュ → index.html 単体上書き → CDN パージ」の順で実行します。

| クラウド | アセット (長期キャッシュ) | index.html (no-cache) | CDN パージ |
|---|---|---|---|
| AWS | `aws s3 sync ./dist --exclude "index.html"` ([code-pipeline-frontend.tf](./iac/aws/code-pipeline-frontend.tf)) | `aws s3 cp ./dist/index.html --cache-control "no-store, no-cache"` | `aws cloudfront create-invalidation --paths "/*"` |
| Azure | `az storage blob upload-batch --content-cache-control 'public, max-age=31536000, immutable'` ([deploy-frontend-azure.yaml](./.github/workflows/deploy-frontend-azure.yaml)) | `az storage blob upload --content-cache-control 'no-store, no-cache'` (index.html 単体を再アップロード) | `az afd endpoint purge --content-paths '/*'` |
| GCP | `gcloud storage rsync --exclude='^index\.html$'` ([deploy-frontend-gcp.yaml](./.github/workflows/deploy-frontend-gcp.yaml)) | `gcloud storage cp --cache-control='no-store, no-cache'` | `gcloud compute url-maps invalidate-cdn-cache --path='/*'` |

CDN 側でも保険を効かせています:

- **AWS CloudFront**: `/index.html` 専用ビヘイビアで `Managed-CachingDisabled` を設定し、 オリジンの Cache-Control が抜けた場合でも CDN レベルで no-cache 動作 ([cloudfront.tf](./iac/aws/cloudfront.tf))
- **GCP Cloud CDN**: バックエンドバケットのキャッシュモードを `USE_ORIGIN_HEADERS` にして GCS の Cache-Control をそのまま尊重 ([load_balancer.tf](./iac/gcp/load_balancer.tf))
- **Azure Front Door**: 既定でオリジンの Cache-Control を尊重するため Storage 側の設定のみで成立

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

# GCP
cd iac/gcp
# 事前に gcloud auth application-default login で ADC 設定
terraform init && terraform apply
# apply 完了後、 GitHub Environment "gcp-main" に Variables / Secrets を一括登録
./setup-github-env.ps1
```

詳細は [IaC仕様書](./docs/iac-spec.md) を参照してください。

#### Azure: GitHub Actions のセットアップ (初回のみ)

Azure 側は **Key Vault に `network_acls` を有効化している**ため、 GitHub Actions ワークフローが Key Vault から secret を直接読み出す方式は使えません。 代わりに **GitHub Environments の Variables/Secrets** に値を登録します。

具体的な手順 (Environment 作成 / `terraform output` から一括登録 / OIDC 用 Secrets / 確認 / ワークフロー実行 / トラブルシューティング / マルチ環境への拡張) は [Azure GitHub Actions セットアップガイド](./docs/azure-github-actions-setup.md) を参照してください。

## AWS 運用

### ログ分析 / Athena

VPCフローログ・ALBアクセスログ・CloudFrontアクセスログ・WAFログをS3へ記録し、Athenaを使ってSQLでクエリできます。partition projection によりパーティションの手動追加は不要です。

クエリ手順・サンプルSQLは [運用・調査コマンドリファレンス](./docs/operations.md#athena---ログ分析クエリ) を参照してください。

### Auroraバックアップ (AWS Backup)

Aurora Serverless v2の自動バックアップ（最大35日）とは別系統で、AWS Backupによる日次・30日保持の長期バックアップを設定しています。

設定詳細は [IaC仕様書 3.5.2](./docs/iac-spec.md#352-バックアップ-aws-backup)、バックアップ一覧・復元手順は [運用・調査コマンド](./docs/operations.md#aurora-aws-backup) を参照してください。

### 監視アラーム

CloudWatch Alarms + SNS で ECS・Aurora の異常を検知します。SNS サブスクリプション（メール・Slack等）は Terraform 管理外のため、デプロイ後に手動登録が必要です。

詳細は [IaC仕様書 3.10](./docs/iac-spec.md#310-監視アラーム-cloudwatch-alarms) を参照してください。

### 自動起動・停止

開発コスト削減のため、EventBridge Scheduler + Step Functions で毎日 21:00 JST に自動停止します（Auto-start はデフォルト無効、有効化すると土日 07:00 JST 起動）。

詳細・手動操作手順は [IaC仕様書 3.13](./docs/iac-spec.md#313-自動起動停止-eventbridge-scheduler--step-functions) を参照してください。

## Azure 運用

Front Door の SKU 選択 (Standard / Premium) については [Front Door の SKU 選択について (Azure)](./docs/azure-frontdoor-sku.md) を参照してください。

### ログ分析

VNet Flow Logs (Traffic Analytics) と Front Door 診断ログを Log Analytics Workspace に集約し、 KQL クエリで分析します (AWS の Athena 相当)。

代表的なクエリは `iac/azure/log_analytics_queries.tf` に `azurerm_log_analytics_saved_search` として登録されており、 Azure Portal の Log Analytics → Saved searches から実行できます:

- VNet Flow: 宛先別バイト数 TOP10 / 拒否フロー一覧
- Front Door: ステータスコード分布 / 4xx・5xx エラーパス TOP20
- Container App: コンソール ERROR 抽出 / システムイベント (リビジョン起動失敗等)

ログは合わせて Storage Account (`*-logs`) にも長期保管 (Hot → Cool@31d → Archive@365d ライフサイクル) されます。

### 監視アラーム

Azure Monitor Metric Alerts + Action Group で Container App と PostgreSQL Flexible Server の異常を検知します:

- **Container App**: `UsageNanoCores` / `WorkingSetBytes` / `RestartCount` (クラッシュループ検知)
- **PostgreSQL**: `cpu_percent` / `memory_percent` / `storage_percent` / `active_connections`

通知先 (メール/Slack等) は Terraform 管理外のため、 デプロイ後に Action Group `<app>-<env>-alarms` に手動登録してください。

### 自動起動・停止

Azure Automation Account + PowerShell Runbook + Schedule で PostgreSQL Flexible Server と Bastion VM を毎日 21:00 JST に自動停止します (`auto_start` は既定で無効、 `auto-start-enabled = true` で土日 07:00 JST 起動)。

Container App は `min_replicas = 0` で **scale-to-zero 動作**するため、 アイドル時は自動でゼロ課金になり、 Runbook での明示停止は不要です。

詳細は [iac/azure/start-stop-resources.tf](./iac/azure/start-stop-resources.tf) を参照してください。

## GCP 運用

### ログ分析 / BigQuery

Cloud Logging のログを sink 経由で BigQuery にエクスポートし、SQL でクエリできます。 partition projection 相当の `use_partitioned_tables = true` で日付パーティションテーブルが自動作成されるため手動管理は不要です。

| Sink 名 | ソース | BigQuery データセット |
|---|---|---|
| `*-lb-logs` | LB request log (`resource.type = http_load_balancer`) | `${app}_${env}_lb_logs` |
| `*-run-logs` | Cloud Run コンテナログ | `${app}_${env}_cloud_run_logs` |
| `*-armor-logs` | Cloud Armor 判定ログ (`enforcedSecurityPolicy.name`) | `${app}_${env}_armor_logs` |
| `*-vpc-flow` | VPC Flow Logs | `${app}_${env}_vpc_flow_logs` |

詳細は [IaC仕様書 5.13](./docs/iac-spec.md#5-gcp-インフラストラクチャ) を参照してください。

### 監視アラーム

Cloud Monitoring Alert Policy + Email 通知チャネルで Cloud Run と Cloud SQL の異常を検知します。 Pub/Sub topic も作成済みで、 Console から通知チャネルを追加する手順は [monitoring_alerts.tf](./iac/gcp/monitoring_alerts.tf) 冒頭のコメント参照。

### 自動起動・停止

Cloud Scheduler + Cloud Workflows で Cloud Run / Cloud SQL / Bastion VM を毎日 21:00 JST に自動停止します (`auto-start` は既定で paused、 土日 07:00 JST 起動)。

### HTTPS / カスタムドメイン

GCP の External Application LB は AWS CloudFront (`*.cloudfront.net`) / Azure Front Door (`*.azurefd.net`) と違い、 マネージドのデフォルト HTTPS ドメインを提供しません。 HTTPS を使うには:

1. ドメインを用意 (任意のレジストラ)
2. A レコードを LB IP に向ける
3. `iac/gcp/terraform.tfvars` に `lb-domain = "your-domain"` 設定
4. `terraform apply` で Google Managed SSL Certificate 自動発行 (15-60分)

未設定時は HTTP のみ (PoC 用)。

## DB 運用 (Prisma マイグレーション / バックアップ・復元)

DB スキーマは Prisma で 3 クラウド共通で管理し (`backend/sandbox-backend/prisma/`)、 自動バックアップも 3 クラウドそれぞれ設定済みです。

| 項目 | 概要 | 詳細 |
|---|---|---|
| マイグレーション | ローカルで `prisma migrate dev` → 本番は踏み台経由で `prisma migrate deploy`。 raw DDL (CREATE EXTENSION / RLS / トリガー等) は migration.sql に手書き | [DB マイグレーション (Prisma)](./docs/db-migration.md) |
| バックアップ・復元 | AWS Backup (30日) / PostgreSQL Flexible Server 組込み (7日) / Cloud SQL 自動バックアップ + PITR。 復元は別エンドポイントとして作成され、 アプリ側で `DATABASE_URL` 切替が必要 | [DB バックアップ・復元](./docs/db-backup-restore.md) |

## セキュリティ強化 (Web脆弱性診断 事前対応)

第三者Web脆弱性診断を見据えたハードニングを適用済みです。適用済み項目・意図的に未適用とした項目・診断実施時の注意事項は [セキュリティ強化ガイド](./docs/security-hardening.md) を参照してください。

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [Frontend仕様書](./docs/frontend-spec.md) | ルーティング、Auth0認証、画面仕様、API通信 |
| [Backend仕様書](./docs/backend-spec.md) | APIエンドポイント、DBスキーマ、JWT認証、OpenTelemetry |
| [IaC仕様書](./docs/iac-spec.md) | AWS/Azure/GCP リソース定義、CI/CD、セキュリティ設計、Trivy スキャン設定 |
| [AWS構成図](./docs/diagrams/aws-architecture.drawio.svg) | AWS インフラ構成図 (Draw.io SVG) |
| [Azure構成図](./docs/diagrams/azure-architecture.drawio.svg) | Azure インフラ構成図 (Draw.io SVG) |
| [CI/CDパイプライン図](./docs/diagrams/cicd-pipeline.drawio.svg) | AWS/Azure CI/CD 比較図 (Draw.io SVG, GCP は未反映) |
| [運用・調査コマンド](./docs/operations.md) | CloudWatch Logs・Athena・ECSヘルスチェック等の調査用コマンド集 |
| [DB マイグレーション (Prisma)](./docs/db-migration.md) | `prisma migrate dev` / `migrate deploy` の流れ、 raw DDL の扱い、 重い DDL の注意点 |
| [DB バックアップ・復元](./docs/db-backup-restore.md) | 3 クラウドのバックアップ機構・リカバリポイント確認・復元実行・接続情報切替・動作確認 |
| [セキュリティ強化ガイド](./docs/security-hardening.md) | Web脆弱性診断事前対応の適用済み項目・未適用項目・診断時の注意事項 |
| [ローカル開発ガイド](./docs/local-dev.md) | Windows / PowerShell 用 `dev-up.ps1` の使い方・前提・スクリプト動作内容 |
| [Azure GitHub Actions セットアップガイド](./docs/azure-github-actions-setup.md) | GitHub Environments への Variables/Secrets 一括登録手順、 OIDC 設定、 トラブルシューティング、 マルチ環境拡張手順 |
| [Front Door SKU 選択ガイド (Azure)](./docs/azure-frontdoor-sku.md) | Standard / Premium の違い、 Standard 採用理由、 Premium への upgrade 手順 |

## 正誤表

書籍の正誤表は [こちら](./appendix/errata.md) をご確認ください。

| No | 内容 | セクション |
|---|---|---|
| 1 | Auth0 API呼び出し用のパーミッション不足 | 1.2.10 IdP(Auth0) |
| 2 | CloudFront VPCオリジン取得用のfilter条件不足 | 2.2.5 CloudFront VPCオリジン |

## コマンドリファレンス

MFA認証・リソース削除・調査コマンド等は [運用・調査コマンドリファレンス](./docs/operations.md) を参照してください。
