# DB バックアップ・復元

3 クラウドそれぞれ自動バックアップを設定済みです。 障害時に復元する手順と、 復元後の動作確認まで通せるように整理しています。

## バックアップ設定の概要

| クラウド | バックアップ機構 | 保持期間 | PITR |
|---|---|---|---|
| AWS | AWS Backup Vault (`sandbox-aws-dev-aurora-vault`) | 30日 | Aurora 自動バックアップ (5日) と併用 |
| Azure | PostgreSQL Flexible Server 組込み | 7日 | 有効 (geo-redundant 任意) |
| GCP | Cloud SQL 自動バックアップ + PITR | 30件保持 / 7日 PITR | 有効 |

## 1. リカバリポイントの確認

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

## 2. 復元の実行

復元先は **新規 DB インスタンス (or クラスタ) として作成される** のが 3 クラウド共通の仕様です。 既存 DB への上書きにはなりません。

**AWS** (`aws backup start-restore-job` → 別 cluster identifier で作成、 さらに `aws rds create-db-instance` で Serverless v2 インスタンスをアタッチ):

→ 詳細は [運用・調査コマンド: Aurora - AWS Backup §リカバリポイントから復元](./operations.md#リカバリポイントから復元) を参照。

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

## 3. 復元後の接続情報切替

復元先は別エンドポイントになるため、 アプリの `DATABASE_URL` を切り替える必要があります。

| クラウド | 接続情報の保管場所 | 切替手段 |
|---|---|---|
| AWS | SSM Parameter Store `/dev/connection_strings/sandbox-aws` | `aws ssm put-parameter --overwrite` → ECS タスク再起動 |
| Azure | Container App env `DATABASE_URL` | `az containerapp update --set-env-vars` |
| GCP | Secret Manager `sandbox-gcp-dev-database-url` | `gcloud secrets versions add` → Cloud Run リビジョン更新 |

## 4. 動作確認 (復元後)

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
