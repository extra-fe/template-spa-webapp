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

開発コスト削減のため、EventBridge Scheduler + Step Functions で毎日 13:00 に自動停止します（Auto-start はデフォルト無効）。

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

Azure Automation Account + PowerShell Runbook + Schedule で PostgreSQL Flexible Server と Bastion VM を毎日 21:00 JST に自動停止します (`auto_start` は既定で無効、 `auto-start-enabled = true` で土日 05:00 起動)。

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

Cloud Scheduler + Cloud Workflows で Cloud Run / Cloud SQL / Bastion VM を毎日 13:00 JST に自動停止します (`auto-start` は既定で paused、 土日 5:00 JST 起動)。

### HTTPS / カスタムドメイン

GCP の External Application LB は AWS CloudFront (`*.cloudfront.net`) / Azure Front Door (`*.azurefd.net`) と違い、 マネージドのデフォルト HTTPS ドメインを提供しません。 HTTPS を使うには:

1. ドメインを用意 (任意のレジストラ)
2. A レコードを LB IP に向ける
3. `iac/gcp/terraform.tfvars` に `lb-domain = "your-domain"` 設定
4. `terraform apply` で Google Managed SSL Certificate 自動発行 (15-60分)

未設定時は HTTP のみ (PoC 用)。

## DB マイグレーション (Prisma)

3 クラウドとも DB スキーマは Prisma で管理しています (`backend/sandbox-backend/prisma/`)。 ローカル開発で migration を生成 → コミット → 本番 DB へ適用 する流れです。

### 1. 新規 migration を作る (DB スキーマ変更時)

ローカル PostgreSQL (Docker) に対して開発します。 `dev-up.ps1` で起動済みであれば DB は立ち上がっています。

```powershell
cd backend/sandbox-backend

# schema.prisma を編集 (テーブル追加 / カラム追加など)
# その後 migration ファイルを生成 + ローカル DB に適用
yarn prisma migrate dev --name add_xxx

# 生成された migration を確認 (prisma/migrations/<timestamp>_add_xxx/migration.sql)
# Prisma Client もこのコマンドで自動再生成される
```

`migration.sql` と `schema.prisma` の変更を commit & push → PR。

> 既存 migration を作り直したい場合は `yarn prisma migrate reset` で DB を再構築。 本番では使わない。

### 2. 既存スキーマの確認 / 軽い変更

```powershell
# 現在の DB と schema の差分を確認 (migration を作らずに)
yarn prisma migrate diff `
  --from-schema-datamodel prisma/schema.prisma `
  --to-schema-datasource prisma/schema.prisma

# Prisma Client のみ再生成 (schema には変更なし)
yarn prisma generate
```

### 3. 本番 DB への migration 適用

各クラウドの DB は Private に配置されているため、 踏み台経由でポートフォワードしてから `prisma migrate deploy` を実行します。 ポートフォワード手順は [運用・調査コマンド: DB接続 (踏み台経由)](./docs/operations.md#db接続-踏み台経由) を参照。

```powershell
# Bastion 経由で localhost:15432 → 各クラウドの DB へポートフォワード済みの状態で実行

# DATABASE_URL を 各クラウドの Secret から取得し host:port を localhost:15432 に置換
$Env:DATABASE_URL = "postgresql://<user>:<pass>@localhost:15432/<dbname>?sslmode=require"

cd backend/sandbox-backend
yarn prisma migrate deploy
```

> `migrate deploy` は `migrate dev` と違い、 未適用の migration を順に適用するだけで対話的なリセット動作はしない。 本番運用ではこちらを使う。

### 4. Prisma で表現できない DDL を実行する場合

Prisma の migration では表現できない / Prisma が自動生成しないものは、 raw SQL を migration ファイルに手書きするか、 psql で直接実行します。 例:

- **PostgreSQL 拡張** (`CREATE EXTENSION pgcrypto;` 等)
- **トリガー / ストアド** (`CREATE TRIGGER` / `CREATE FUNCTION`)
- **行レベルセキュリティ** (`ENABLE ROW LEVEL SECURITY` / `CREATE POLICY`)
- **複合インデックス・部分インデックス・GIN/GIST**
- **CHECK 制約・複雑な UNIQUE 制約**
- **データバックフィル** (スキーマ変更と同時に既存データを書き換える)
- **ロール / 権限** (`CREATE ROLE`, `GRANT`)
- **VIEW / MATERIALIZED VIEW**

#### A. Prisma migration ファイルに DDL を手書き (推奨)

履歴管理されるため、 本番含めて再現性が担保される。

```powershell
cd backend/sandbox-backend

# --create-only で migration ファイルだけ生成 (DB に適用しない)
yarn prisma migrate dev --create-only --name add_pgcrypto_extension

# 生成された prisma/migrations/<timestamp>_add_pgcrypto_extension/migration.sql を編集
# 末尾に raw SQL を追記
#   CREATE EXTENSION IF NOT EXISTS pgcrypto;
#   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_race_held_on ON "Race" USING btree (held_on);

# 編集後に適用 (ローカル DB)
yarn prisma migrate dev
```

> `db pull` で schema.prisma を実 DB に合わせて更新すると、 Prisma が認識可能な範囲 (テーブル/カラム/インデックス等) は反映される。 認識外の DDL (RLS / トリガー等) は migration.sql の手書きが正となる。

#### B. psql で直接 DDL を実行 (ホットフィックス / 検証用)

緊急対応や、 Prisma 管理外で恒久的に持つもの (例: 監視用 VIEW を別 schema に作る) は psql で直接実行。

```powershell
# 踏み台経由で localhost:15432 にポートフォワード済みの状態

# ファイル経由で実行 (推奨: 履歴が残せる)
psql "$Env:DATABASE_URL" -f .\ddl\add_pgcrypto.sql

# ワンライナーで実行
psql "$Env:DATABASE_URL" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

# トランザクション内で実行 (失敗時に ROLLBACK)
psql "$Env:DATABASE_URL" -1 -f .\ddl\add_rls.sql
```

> psql 直実行は **Prisma の migration 履歴 (`_prisma_migrations`) に残らない**ため、 次の `migrate dev` 時に差分として検出される可能性がある。 恒久対応は A. の migration 手書きに含めること。

#### C. 本番 DDL を反映する際の運用フロー

```
1. ローカル DB で A or B で DDL を試す
2. A. なら migration.sql を確定して commit & push & PR
3. 本番 (各クラウド DB) に踏み台経由で接続
4. yarn prisma migrate deploy で適用
   または psql -f で raw SQL を実行
5. _prisma_migrations / pg_extension / pg_indexes 等で適用結果を確認
```

#### D. 重い DDL (CREATE INDEX / ALTER COLUMN 等) の注意

- `CREATE INDEX` は `CONCURRENTLY` 付きでオンライン作成 (トランザクション外で実行)
- `ALTER COLUMN` で型変更する場合、 テーブルサイズに比例して時間がかかる
- 大きな DDL は **メンテナンスウィンドウ** に実施 (cloud 別 maintenance_window 設定参照)

### 5. 適用後の動作確認

```powershell
# Migration 履歴の確認 (_prisma_migrations テーブル)
psql "$Env:DATABASE_URL" -c "SELECT migration_name, started_at, finished_at FROM _prisma_migrations ORDER BY started_at DESC LIMIT 5;"

# テーブル一覧
psql "$Env:DATABASE_URL" -c "\dt"

# 行数チェック (例)
psql "$Env:DATABASE_URL" -c "SELECT count(*) FROM \"Race\";"

# 拡張機能の確認 (DDL で CREATE EXTENSION した場合)
psql "$Env:DATABASE_URL" -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"

# インデックス確認 (DDL で CREATE INDEX した場合)
psql "$Env:DATABASE_URL" -c "SELECT schemaname, tablename, indexname FROM pg_indexes WHERE schemaname = 'public' ORDER BY tablename, indexname;"
```

ヘルスチェック・API スモークテストも実施:

```powershell
curl https://<your-domain>/api/guest/connect-test
curl https://<your-domain>/api/races   # 必要に応じて Bearer token 付き
```

## DB バックアップ・復元

3 クラウドそれぞれ自動バックアップを設定済みです。 障害時に復元する手順と、 復元後の動作確認まで通せるように整理しています。

### バックアップ設定の概要

| クラウド | バックアップ機構 | 保持期間 | PITR |
|---|---|---|---|
| AWS | AWS Backup Vault (`sandbox-aws-dev-aurora-vault`) | 30日 | Aurora 自動バックアップ (5日) と併用 |
| Azure | PostgreSQL Flexible Server 組込み | 7日 | 有効 (geo-redundant 任意) |
| GCP | Cloud SQL 自動バックアップ + PITR | 30件保持 / 7日 PITR | 有効 |

### 1. リカバリポイントの確認

**AWS**:

```powershell
aws backup list-recovery-points-by-backup-vault `
  --backup-vault-name sandbox-aws-dev-aurora-vault `
  --query 'RecoveryPoints[].[RecoveryPointArn,CreationDate,Status]' --output table
```

**Azure**:

```powershell
az postgres flexible-server backup list `
  --resource-group rg-sandbox-dev `
  --name sandbox-dev-db-server `
  --output table
```

**GCP**:

```powershell
gcloud sql backups list --instance=sandbox-gcp-dev-db --limit=10
```

### 2. 復元の実行

復元先は **新規 DB インスタンス (or クラスタ) として作成される** のが 3 クラウド共通の仕様です。 既存 DB への上書きにはなりません。

**AWS** (`aws backup start-restore-job` → 別 cluster identifier で作成、 さらに `aws rds create-db-instance` で Serverless v2 インスタンスをアタッチ):

→ 詳細は [運用・調査コマンド: Aurora - AWS Backup §リカバリポイントから復元](./docs/operations.md#リカバリポイントから復元) を参照。

**Azure** (point-in-time-restore で別 server 名で作成):

```powershell
az postgres flexible-server restore `
  --resource-group rg-sandbox-dev `
  --name sandbox-dev-db-server-restored `
  --source-server sandbox-dev-db-server `
  --restore-time "2026-05-27T03:00:00Z"
```

**GCP** (別 instance 名で復元):

```powershell
# バックアップ ID を取得
$BACKUP_ID = gcloud sql backups list --instance=sandbox-gcp-dev-db `
  --limit=1 --format="value(id)"

# 別インスタンス名で復元 (Cloud SQL は同名インスタンスへの上書きも可能だが、検証用は別名推奨)
gcloud sql backups restore $BACKUP_ID `
  --restore-instance=sandbox-gcp-dev-db-restored `
  --backup-instance=sandbox-gcp-dev-db
```

### 3. 復元後の接続情報切替

復元先は別エンドポイントになるため、 アプリの `DATABASE_URL` を切り替える必要があります。

| クラウド | 接続情報の保管場所 | 切替手段 |
|---|---|---|
| AWS | SSM Parameter Store `/dev/connection_strings/sandbox-aws` | `aws ssm put-parameter --overwrite` → ECS タスク再起動 |
| Azure | Container App env `DATABASE_URL` | `az containerapp update --set-env-vars` |
| GCP | Secret Manager `sandbox-gcp-dev-database-url` | `gcloud secrets versions add` → Cloud Run リビジョン更新 |

### 4. 動作確認 (復元後)

復元 DB へ踏み台経由で接続 (踏み台のポートフォワード先 IP/FQDN を**復元先の DB エンドポイント**に変更):

```powershell
# ポートフォワード設定後、 復元 DB のテーブル一覧と件数をスポット確認
psql "$DATABASE_URL" -c "\dt"
psql "$DATABASE_URL" -c "SELECT 'Race' AS tbl, count(*) FROM \"Race\" UNION ALL SELECT 'User', count(*) FROM \"User\";"

# Prisma migration 履歴も継承されているか確認
psql "$DATABASE_URL" -c "SELECT migration_name, finished_at FROM _prisma_migrations ORDER BY started_at DESC LIMIT 5;"
```

接続情報をアプリ側に切り替えた後、 API のスモークチェック:

```powershell
curl https://<your-domain>/api/guest/connect-test
# {"message":"GET api/guest/connect-test ok", ...} が返れば正常
```

> 復元元のインスタンスは復元成功後に削除する判断 (コスト削減) も検討。 タグやメモで紛失防止すること。

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
