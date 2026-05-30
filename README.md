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
| 静的解析 (CI) | GitHub Actions (ESLint + `tsc --noEmit`, PR ゲート) |
| IaC 静的解析 (CI) | GitHub Actions (terraform fmt / validate / tflint / Trivy misconfig, PR ゲート) |
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
    └── workflows/               # GitHub Actions CI (Trivy scan, Lint/型チェック, Azure/GCP deploy)
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

## クラウド別 運用

ログ分析・監視アラーム・自動起動停止・HTTPS など、 3 クラウドの運用構成の違いを以下にまとめます。 各項目の詳細・手順は [クラウド別 運用ガイド](./docs/cloud-operations.md) を参照してください。

| 観点 | AWS | Azure | GCP |
|---|---|---|---|
| ログ分析基盤 | Athena + Glue Data Catalog (S3, partition projection) | Log Analytics + KQL (saved searches) | BigQuery (Cloud Logging sink, 日付パーティション) |
| 監視アラーム | CloudWatch Alarms + SNS | Azure Monitor Metric Alerts + Action Group | Cloud Monitoring Alert Policy + Email |
| 監視対象 | ECS / Aurora | Container App / PostgreSQL Flexible Server | Cloud Run / Cloud SQL |
| 通知先の登録 | SNS サブスクリプションを手動登録 | Action Group に手動登録 | 通知チャネルを手動追加 |
| 自動起動・停止 | EventBridge Scheduler + Step Functions | Automation Account + PowerShell Runbook | Cloud Scheduler + Cloud Workflows |
| アイドル時の課金 | 自動停止で抑制 | Container App は scale-to-zero で自動ゼロ課金 | 自動停止で抑制 (Cloud Run はリクエスト課金) |
| HTTPS デフォルトドメイン | `*.cloudfront.net` | `*.azurefd.net` | なし (Google Managed SSL = ドメイン必須) |

自動起動・停止のスケジュールは 3 クラウド共通で、 **停止: 毎日 21:00 JST / 起動: 土日 07:00 JST** (起動は既定で無効) です。

## DB 運用 (Prisma マイグレーション / バックアップ・復元)

DB スキーマは Prisma で 3 クラウド共通で管理し (`backend/sandbox-backend/prisma/`)、 自動バックアップも 3 クラウドそれぞれ設定済みです。

| 項目 | 概要 | 詳細 |
|---|---|---|
| マイグレーション | ローカルで `prisma migrate dev` → 本番は踏み台経由で `prisma migrate deploy`。 raw DDL (CREATE EXTENSION / RLS / トリガー等) は migration.sql に手書き | [DB マイグレーション (Prisma)](./docs/db-migration.md) |
| バックアップ・復元 | AWS Backup (30日) / PostgreSQL Flexible Server 組込み (7日) / Cloud SQL 自動バックアップ + PITR。 復元は別エンドポイントとして作成され、 アプリ側で `DATABASE_URL` 切替が必要 | [DB バックアップ・復元](./docs/db-backup-restore.md) |

## セキュリティ強化 (Web脆弱性診断 事前対応)

第三者Web脆弱性診断を見据えたハードニングを適用済みです。適用済み項目・意図的に未適用とした項目・診断実施時の注意事項は [セキュリティ強化ガイド](./docs/security-hardening.md) を参照してください。

## 静的解析 (Lint / 型チェック) の CI ゲート

TypeScript (backend / frontend) の ESLint と型チェックを **PR 時点で自動検出する CI ゲート**を用意しています。これまでローカルの `yarn lint` 任せだった lint / 型エラー / 規約逸脱を、`main` への PR でブロックします。`lint:ci` は `--max-warnings 0` の非破壊実行で Trivy と並列に走り、対象外 PR では skipped となるようジョブレベルでパスフィルタしています。

構成・設計上のポイント・Branch protection 必須化手順の詳細は [静的解析 (Lint / 型チェック) の CI ゲート](./docs/ci-static-analysis.md) を参照してください。

## IaC 静的解析 (Terraform) の CI ゲート

`iac/` 配下の変更を含む PR に対して **terraform fmt / validate / tflint / Trivy misconfig** を自動実行する CI ゲート (`ci-iac.yaml`) を用意しています。フォーマット崩れ・構文エラー・プロバイダ固有の命名規則違反・IaC 設定ミス (暗号化未設定・パブリックアクセス許可等) を PR 時点で検出します。

- **terraform fmt**: 全クラウド (`iac/aws` / `iac/azure` / `iac/gcp`) を一括チェック
- **terraform validate**: `terraform init -backend=false` でプロバイダのみ取得してから構文検証（クラウド認証不要）
- **tflint**: 各クラウドの `.tflint.hcl` でプロバイダ固有ルールセット (`tflint-ruleset-aws` / `azurerm` / `google`) を有効化
- **Trivy misconfig**: CRITICAL/HIGH の設定ミスを gate 化。既知の意図的な設定は `iac/<cloud>/.trivyignore` で抑制

構成・運用方針・Required status checks 設定手順は [IaC仕様書 §6.2](./docs/iac-spec.md) を参照してください。

### PR ごとに複数の CI ワークフローが動くのは正常

すべての CI ワークフロー (`ci-iac.yaml` / `ci-frontend.yaml` / `ci-backend.yaml`) は `pull_request: branches: [main]` をトリガーに登録しているため、どのファイルを変更した PR でも全ワークフローが起動します。ただし **実際に処理をするかどうかはジョブレベルのパスフィルタで制御**しており、対象外のファイルしか変更していない場合は後続ジョブがすべて **skipped（= 成功扱い）** で即終了します。

この設計にしている理由: ワークフローレベルで `paths` フィルタを付けると、対象外 PR ではワークフロー自体が起動しなくなります。Required status check に登録したジョブが「Expected — Waiting for status」のまま pending になり、PR がマージ不能になる問題を防ぐためです。

## 実装時の検討事項 (アプリ側)

テンプレート実装時に洗い出したアプリケーション側 (frontend / backend) の検討事項 (排他制御・例外制御・日時/TZ・i18n・テスト・依存バージョンアップ等) は、今後の改善対象として GitHub Issue で管理しています。一覧は [実装時の検討事項 (アプリ側)](./docs/app-considerations.md) を参照してください。

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [Frontend仕様書](./docs/frontend-spec.md) | ルーティング、Auth0認証、画面仕様、API通信 |
| [Backend仕様書](./docs/backend-spec.md) | APIエンドポイント、DBスキーマ、JWT認証、OpenTelemetry |
| [IaC仕様書](./docs/iac-spec.md) | AWS/Azure/GCP リソース定義、CI/CD、セキュリティ設計、Trivy スキャン設定 |
| [AWS構成図](./docs/diagrams/aws-architecture.drawio.svg) | AWS インフラ構成図 (Draw.io SVG) |
| [Azure構成図](./docs/diagrams/azure-architecture.drawio.svg) | Azure インフラ構成図 (Draw.io SVG) |
| [CI/CDパイプライン図](./docs/diagrams/cicd-pipeline.drawio.svg) | AWS/Azure CI/CD 比較図 (Draw.io SVG, GCP は未反映) |
| [クラウド別 運用ガイド](./docs/cloud-operations.md) | AWS/Azure/GCP のログ分析・監視アラーム・自動起動停止・HTTPS の構成と手順 |
| [運用・調査コマンド](./docs/operations.md) | CloudWatch Logs・Athena・ECSヘルスチェック等の調査用コマンド集 |
| [DB マイグレーション (Prisma)](./docs/db-migration.md) | `prisma migrate dev` / `migrate deploy` の流れ、 raw DDL の扱い、 重い DDL の注意点 |
| [DB バックアップ・復元](./docs/db-backup-restore.md) | 3 クラウドのバックアップ機構・リカバリポイント確認・復元実行・接続情報切替・動作確認 |
| [セキュリティ強化ガイド](./docs/security-hardening.md) | Web脆弱性診断事前対応の適用済み項目・未適用項目・診断時の注意事項 |
| [静的解析 (Lint / 型チェック) の CI ゲート](./docs/ci-static-analysis.md) | backend/frontend の ESLint・型チェック PR ゲートの構成、`lint:ci` の挙動、ジョブレベルパスフィルタ、Required status checks 必須化手順 |
| [ローカル開発ガイド](./docs/local-dev.md) | Windows / PowerShell 用 `dev-up.ps1` の使い方・前提・スクリプト動作内容 |
| [Azure GitHub Actions セットアップガイド](./docs/azure-github-actions-setup.md) | GitHub Environments への Variables/Secrets 一括登録手順、 OIDC 設定、 トラブルシューティング、 マルチ環境拡張手順 |
| [Front Door SKU 選択ガイド (Azure)](./docs/azure-frontdoor-sku.md) | Standard / Premium の違い、 Standard 採用理由、 Premium への upgrade 手順 |
| [実装時の検討事項 (アプリ側)](./docs/app-considerations.md) | アプリ側の未対応・方針未確定事項 (設計/挙動・テスト・静的解析・依存バージョンアップ) と対応 Issue 一覧 |

## 正誤表

書籍の正誤表は [こちら](./appendix/errata.md) をご確認ください。

| No | 内容 | セクション |
|---|---|---|
| 1 | Auth0 API呼び出し用のパーミッション不足 | 1.2.10 IdP(Auth0) |
| 2 | CloudFront VPCオリジン取得用のfilter条件不足 | 2.2.5 CloudFront VPCオリジン |

## コマンドリファレンス

MFA認証・リソース削除・調査コマンド等は [運用・調査コマンドリファレンス](./docs/operations.md) を参照してください。
