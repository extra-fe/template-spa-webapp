# クラウド別 運用ガイド

AWS / Azure / GCP それぞれの運用構成 (ログ分析・監視アラーム・自動起動停止・HTTPS 等) の詳細です。3 クラウドの違いのサマリーは [README のクラウド別 運用](../README.md#クラウド別-運用) を参照してください。

## AWS 運用

### ログ分析 / Athena

VPCフローログ・ALBアクセスログ・CloudFrontアクセスログ・WAFログをS3へ記録し、Athenaを使ってSQLでクエリできます。partition projection によりパーティションの手動追加は不要です。

クエリ手順・サンプルSQLは [運用・調査コマンドリファレンス](./operations.md#athena---ログ分析クエリ) を参照してください。

### Auroraバックアップ (AWS Backup)

Aurora Serverless v2の自動バックアップ（最大35日）とは別系統で、AWS Backupによる日次・30日保持の長期バックアップを設定しています。

設定詳細は [IaC仕様書 3.5.2](./iac-spec.md#352-バックアップ-aws-backup)、バックアップ一覧・復元手順は [運用・調査コマンド](./operations.md#aurora-aws-backup) を参照してください。

### 監視アラーム

CloudWatch Alarms + SNS で ECS・Aurora の異常を検知します。SNS サブスクリプション（メール・Slack等）は Terraform 管理外のため、デプロイ後に手動登録が必要です。

詳細は [IaC仕様書 3.10](./iac-spec.md#310-監視アラーム-cloudwatch-alarms) を参照してください。

### 自動起動・停止

開発コスト削減のため、EventBridge Scheduler + Step Functions で毎日 21:00 JST に自動停止します（Auto-start はデフォルト無効、有効化すると土日 07:00 JST 起動）。

詳細・手動操作手順は [IaC仕様書 3.13](./iac-spec.md#313-自動起動停止-eventbridge-scheduler--step-functions) を参照してください。

## Azure 運用

Front Door の SKU 選択 (Standard / Premium) については [Front Door の SKU 選択について (Azure)](./azure-frontdoor-sku.md) を参照してください。

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

詳細は [iac/azure/start-stop-resources.tf](../iac/azure/start-stop-resources.tf) を参照してください。

## GCP 運用

### ログ分析 / BigQuery

Cloud Logging のログを sink 経由で BigQuery にエクスポートし、SQL でクエリできます。 partition projection 相当の `use_partitioned_tables = true` で日付パーティションテーブルが自動作成されるため手動管理は不要です。

| Sink 名 | ソース | BigQuery データセット |
|---|---|---|
| `*-lb-logs` | LB request log (`resource.type = http_load_balancer`) | `${app}_${env}_lb_logs` |
| `*-run-logs` | Cloud Run コンテナログ | `${app}_${env}_cloud_run_logs` |
| `*-armor-logs` | Cloud Armor 判定ログ (`enforcedSecurityPolicy.name`) | `${app}_${env}_armor_logs` |
| `*-vpc-flow` | VPC Flow Logs | `${app}_${env}_vpc_flow_logs` |

詳細は [IaC仕様書 5.13](./iac-spec.md#5-gcp-インフラストラクチャ) を参照してください。

### 監視アラーム

Cloud Monitoring Alert Policy + Email 通知チャネルで Cloud Run と Cloud SQL の異常を検知します。 Pub/Sub topic も作成済みで、 Console から通知チャネルを追加する手順は [monitoring_alerts.tf](../iac/gcp/monitoring_alerts.tf) 冒頭のコメント参照。

### 自動起動・停止

Cloud Scheduler + Cloud Workflows で Cloud Run / Cloud SQL / Bastion VM を毎日 21:00 JST に自動停止します (`auto-start` は既定で paused、 土日 07:00 JST 起動)。

### HTTPS / カスタムドメイン

GCP の External Application LB は AWS CloudFront (`*.cloudfront.net`) / Azure Front Door (`*.azurefd.net`) と違い、 マネージドのデフォルト HTTPS ドメインを提供しません。 HTTPS を使うには:

1. ドメインを用意 (任意のレジストラ)
2. A レコードを LB IP に向ける
3. `iac/gcp/terraform.tfvars` に `lb-domain = "your-domain"` 設定
4. `terraform apply` で Google Managed SSL Certificate 自動発行 (15-60分)

未設定時は HTTP のみ (PoC 用)。
