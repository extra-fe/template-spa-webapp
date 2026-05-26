# 運用・調査コマンドリファレンス

調査・デバッグ時に使用するコマンド集です。
`<AWSアカウントID>` / `<バケット名>` 等のプレースホルダは実際の値に置き換えて実行してください。

---

## AWS認証

```powershell
# 指定プロファイルの認証情報を環境変数に反映
aws configure export-credentials --profile <プロファイル名> --format powershell | Invoke-Expression
```

### MFAトークン取得

```powershell
$mfa_device='[識別子]'

$Env:AWS_ACCESS_KEY_ID=''
$Env:AWS_SECRET_ACCESS_KEY=''
$Env:AWS_SESSION_TOKEN=''

$token=Read-Host
$cre=(aws sts get-session-token --serial-number $mfa_device --token-code $token) | ConvertFrom-Json

$Env:AWS_ACCESS_KEY_ID=$cre.Credentials.AccessKeyId
$Env:AWS_SECRET_ACCESS_KEY=$cre.Credentials.SecretAccessKey
$Env:AWS_SESSION_TOKEN=$cre.Credentials.SessionToken
```

---

## CloudWatch Logs - ECSログ取得

指定時刻の前後10分のECSログを取得します。

```powershell
$baseTime = [DateTimeOffset]::Parse("2026-05-09T15:54:25+09:00")
$startTime = $baseTime.AddMinutes(-10).ToUnixTimeMilliseconds()
$endTime = $baseTime.ToUnixTimeMilliseconds()

aws logs filter-log-events `
  --log-group-name /ecs/sandbox-aws-dev-log `
  --start-time $startTime `
  --end-time $endTime `
  | ConvertFrom-Json `
  | Select-Object -ExpandProperty events `
  | ForEach-Object {
      [PSCustomObject]@{
          timestamp = [DateTimeOffset]::FromUnixTimeMilliseconds($_.timestamp).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
          message   = $_.message
      }
  } `
  | Format-List
```

---

## Athena - ALBアクセスログ分析

### テーブル作成

```sql
CREATE EXTERNAL TABLE alb_logs (
  type string,
  time string,
  elb string,
  client_ip string,
  client_port int,
  target_ip string,
  target_port int,
  request_processing_time double,
  target_processing_time double,
  response_processing_time double,
  elb_status_code int,
  target_status_code string,
  received_bytes bigint,
  sent_bytes bigint,
  request_verb string,
  request_url string,
  request_proto string,
  user_agent string,
  ssl_cipher string,
  ssl_protocol string,
  target_group_arn string,
  trace_id string,
  domain_name string,
  chosen_cert_arn string,
  matched_rule_priority string,
  request_creation_time string,
  actions_executed string,
  redirect_url string,
  error_reason string,
  target_port_list string,
  target_status_code_list string,
  classification string,
  classification_reason string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES (
  'serialization.format' = '1',
  'input.regex' = '([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*):([0-9]*) ([^ ]*)[:-]([0-9]*) ([-.0-9]*) ([-.0-9]*) ([-.0-9]*) (|[-0-9]*) (-|[-0-9]*) ([-0-9]*) ([-0-9]*) \"([^ ]*) (.*) (- |[^ ]*)\" \"([^\"]*)\" ([A-Z0-9-_]+) ([A-Za-z0-9.-]*) ([^ ]*) \"([^\"]*)\" \"([^\"]*)\" \"([^\"]*)\" ([-.0-9]*) ([^ ]*) \"([^\"]*)\" \"([^\"]*)\" \"([^ ]*)\" \"([^\s]+?)\" \"([^\s]+)\" \"([^ ]*)\" \"([^ ]*)\"'
)
LOCATION 's3://<バケット名>/AWSLogs/<AWSアカウントID>/elasticloadbalancing/ap-northeast-1/2026/05/';
```

> `<バケット名>`: `alb.tf` の `aws_s3_bucket.alb_logs` で作成されたバケット名
> `<AWSアカウントID>`: 12桁のAWSアカウントID

---

## Athena - ログ分析クエリ

VPCフローログ・ALBアクセスログ・CloudFrontアクセスログ・WAFログ・ECSコンテナログを Athena で分析するためのクエリ集です。

**partition projection について**

Glueテーブルに partition projection を設定しているため、新しい日付のログが届いても `MSCK REPAIR TABLE` や手動でのパーティション追加は不要です。クエリ実行時にAthenaが日付範囲（過去1年〜現在）からS3パスを自動計算して参照します。

### VPCフローログ

VPC全体のトラフィック（ACCEPT / REJECT 両方）をS3へ約10分ごとに記録しています。

**クエリ手順**

1. Athena コンソールを開く
2. ワークグループを `{app-name}-{environment}-vpc-flow-logs` に切替える
3. データベース `{app_name}_{environment}_vpc_flow_logs` → テーブル `vpc_flow_logs` を選択

```sql
-- 直近1日の REJECT トップ10（不審な着信の洗い出し）
SELECT srcaddr, dstport, count(*) AS cnt
FROM vpc_flow_logs
WHERE date >= date_format(current_date - interval '1' day, '%Y/%m/%d')
  AND action = 'REJECT'
GROUP BY srcaddr, dstport
ORDER BY cnt DESC LIMIT 10;

-- 通信量トップ（NAT料金が膨らんだときの犯人探し）
SELECT srcaddr, dstaddr, sum(bytes)/1024/1024 AS mb
FROM vpc_flow_logs
WHERE date = date_format(current_date, '%Y/%m/%d')
GROUP BY srcaddr, dstaddr
ORDER BY mb DESC LIMIT 20;
```

### ALBアクセスログ

ALBへのリクエスト（レイテンシ・ステータスコード・URL等）をS3へ記録しています。

**クエリ手順**

1. Athena コンソールを開く
2. ワークグループを `{app-name}-{environment}-alb-logs` に切替える
3. データベース `{app_name}_{environment}_alb_logs` → テーブル `alb_access_logs` を選択

```sql
-- 直近1日のアクセスログ（新しい順）
SELECT time, elb_status_code, request_verb, request_url, target_processing_time
FROM alb_access_logs
WHERE day = date_format(current_date, '%Y/%m/%d')
ORDER BY time DESC LIMIT 10;

-- レスポンスが遅いリクエストトップ10（パフォーマンス調査）
SELECT request_url, avg(target_processing_time) AS avg_sec, count(*) AS cnt
FROM alb_access_logs
WHERE day = date_format(current_date, '%Y/%m/%d')
  AND target_processing_time > 0
GROUP BY request_url
ORDER BY avg_sec DESC LIMIT 10;
```

### CloudFrontアクセスログ

CloudFrontへの全リクエスト（メソッド・ステータス・レイテンシ・エッジロケーション等）をS3へ記録しています。

**クエリ手順**

1. Athena コンソールを開く
2. ワークグループを `{app-name}-{environment}-cloudfront-logs` に切替える
3. データベース `{app_name}_{environment}_cloudfront_logs` → テーブル `cloudfront_access_logs` を選択

```sql
-- 直近1日の 4xx/5xx エラートップ10
SELECT cs_uri_stem, sc_status, count(*) AS cnt
FROM cloudfront_access_logs
WHERE day = date_format(current_date, '%Y/%m/%d')
  AND sc_status >= 400
GROUP BY cs_uri_stem, sc_status
ORDER BY cnt DESC LIMIT 10;

-- レスポンスが遅いリクエストトップ10（パフォーマンス調査）
SELECT cs_uri_stem, avg(time_taken) AS avg_sec, count(*) AS cnt
FROM cloudfront_access_logs
WHERE day = date_format(current_date, '%Y/%m/%d')
GROUP BY cs_uri_stem
ORDER BY avg_sec DESC LIMIT 10;
```

> **パーティション指定の注意点**
> - `day` は必ず指定してください。省略すると過去1年分（365日 × 24時間）を全スキャンします。
> - `hour` を追加すると1時間分のみに絞れます（例: `AND hour = '13'`）。
> - `hour` はパーティションキーが **string 型**のため、整数ではなくクォートした文字列で指定します。
> - `sc_range_start` / `sc_range_end` はRangeリクエスト以外では常に NULL になります（正常）。

### WAFログ

CloudFront WAF v2 の判定結果（ALLOW / BLOCK / COUNT）をS3へ記録しています。

**クエリ手順**

1. Athena コンソールを開く
2. ワークグループを `{app-name}-{environment}-waf-logs` に切替える
3. データベース `{app_name}_{environment}_waf_logs` → テーブル `waf_logs` を選択

```sql
-- 直近1日のブロックトップ10（不審なIPの特定）
SELECT httprequest.clientip, httprequest.uri, count(*) AS cnt
FROM waf_logs
WHERE day = date_format(current_date, '%Y/%m/%d')
  AND action = 'BLOCK'
GROUP BY httprequest.clientip, httprequest.uri
ORDER BY cnt DESC LIMIT 10;

-- ブロック原因ルールの内訳
SELECT terminatingruleid, count(*) AS cnt
FROM waf_logs
WHERE day = date_format(current_date, '%Y/%m/%d')
  AND action = 'BLOCK'
GROUP BY terminatingruleid
ORDER BY cnt DESC;
```

### ECSコンテナログ

ECSアプリコンテナのログ（FireLens / Fluent Bit 経由）をS3へ記録しています。ヘルスチェックのログは除外されています。

**クエリ手順**

1. Athena コンソールを開く
2. ワークグループを `{app-name}-{environment}-ecs-logs` に切替える
3. データベース `{app_name}_{environment}_ecs_logs` → テーブル `ecs_logs` を選択

```sql
-- 特定日のログを表示
SELECT log, container_name, source
FROM ecs_logs
WHERE date = '2026/05/17'
LIMIT 50;

-- エラーログの抽出
SELECT log, container_name
FROM ecs_logs
WHERE date = date_format(current_date, '%Y/%m/%d')
  AND lower(log) LIKE '%error%'
LIMIT 50;
```

### S3保管ポリシー（共通）

VPCフローログ・ALBアクセスログ・CloudFrontアクセスログ・WAFログ・ECSコンテナログ共通のライフサイクルポリシーです。

| 期間 | ストレージクラス | Athenaクエリ |
|---|---|---|
| 0〜30日 | Standard | 可 |
| 31〜365日 | Standard-IA | 可（コスト約60%減） |
| 365日以降 | Glacier | 不可（保管のみ） |

> Athenaクエリ結果は7日後に自動削除されます（`alb.tf` の `athena_results` バケットライフサイクル設定）。

---

## FireLens カスタムイメージのビルド＆デプロイ

ECSのログルーター（Fluent Bit）はカスタムイメージを使用しています。
`iac/aws/fluent-bit/` 配下のファイル（`extra.conf` / `remove_ansi.lua` / `Dockerfile`）を変更した場合は、イメージの再ビルドとECSサービスの再起動が必要です。

### ビルド＆ECRプッシュ

`iac/aws/fluent-bit/` ディレクトリで実行してください。

```powershell
$ACCOUNT_ID = (aws sts get-caller-identity | ConvertFrom-Json).Account
$REGION = "ap-northeast-1"
$REPO = "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/dev/fluent-bit"

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
docker build -t dev/fluent-bit .
docker tag dev/fluent-bit:latest "${REPO}:latest"
docker push "${REPO}:latest"
```

### ECSサービスの再起動（新イメージを反映）

```powershell
aws ecs update-service `
  --cluster sandbox-aws-dev-cluster `
  --service sandbox-aws-dev-service `
  --force-new-deployment
```

### 設定変更時の対応フロー

| 変更内容 | 必要な作業 |
|---|---|
| `extra.conf` / `remove_ansi.lua` の変更 | ビルド＆プッシュ → ECSサービス再起動 |
| `Dockerfile` のベースイメージ変更 | ビルド＆プッシュ → ECSサービス再起動 |
| ECSタスク定義（環境変数等）の変更 | `terraform apply` → ECSサービス再起動 |

---

## ECS - タスク強制再デプロイ

SSMパラメータストアの値を変更した場合（DATABASE_URL等）、実行中のタスクには自動反映されません。
以下のコマンドで新しいタスクを起動し、最新のパラメータ値を反映させてください。

```powershell
aws ecs update-service `
  --cluster sandbox-aws-dev-cluster `
  --service sandbox-aws-dev-service `
  --force-new-deployment
```

> SSMパラメータの値はタスク起動時にのみ取得されるため、`terraform apply` 後は必ずタスクの再デプロイが必要です。

---

## ECS - ECS Execの有効・無効切り替え

ECS Execは `ecs.tf` の `enable_execute_command = true` で有効化されています。
コンテナへのシェル接続が可能になるため、調査・デバッグが不要な場合は無効化してください。

```powershell
# 無効化
aws ecs update-service `
  --cluster sandbox-aws-dev-cluster `
  --service sandbox-aws-dev-service `
  --enable-execute-command false

# 有効化
aws ecs update-service `
  --cluster sandbox-aws-dev-cluster `
  --service sandbox-aws-dev-service `
  --enable-execute-command true
```

> CLIでの変更は一時的な対処です。恒久的に変更する場合は `ecs.tf` の `enable_execute_command` を変更して `terraform apply` してください。

---

## ECS - VPCエンドポイント経由の通信確認

VPCエンドポイント（Interface）が有効な場合、エンドポイントのDNS名がVPC内のプライベートIPに解決されます。
ECS Execでコンテナに接続し、DNS解決結果のIPアドレスで判定します。

```powershell
# ECS Execでコンテナに接続
$taskArn = (aws ecs list-tasks `
  --cluster sandbox-aws-dev-cluster `
  --service-name sandbox-aws-dev-service `
  --query 'taskArns[0]' `
  --output text)

aws ecs execute-command `
  --cluster sandbox-aws-dev-cluster `
  --task $taskArn `
  --container sandbox-aws `
  --command "/bin/sh" `
  --interactive
```

コンテナ内で実行:

```sh
# ECR APIエンドポイントのDNS解決
node -e "require('dns').lookup('api.ecr.ap-northeast-1.amazonaws.com', (err, addr) => console.log(addr))"

# CloudWatch LogsエンドポイントのDNS解決
node -e "require('dns').lookup('logs.ap-northeast-1.amazonaws.com', (err, addr) => console.log(addr))"
```

| 返ってくるIP | 意味 |
|---|---|
| VPC CIDRの範囲内（`vpc_cidr_block` 変数で設定した範囲） | VPCエンドポイント経由 ✅ |
| パブリックIP | Regional NAT Gateway経由 ❌ |

---

## ECS - ターゲットグループのヘルスチェック確認

```powershell
$targetGroupArn = (aws ecs describe-services `
   --cluster sandbox-aws-dev-cluster `
   --services sandbox-aws-dev-service `
   --query 'services[0].loadBalancers[0].targetGroupArn' `
   --output text)

aws elbv2 describe-target-health `
   --target-group-arn $targetGroupArn `
   --query 'TargetHealthDescriptions[*].[Target.Id,Target.Port,TargetHealth.State,TargetHealth.Description]' `
   --output table
```

---

## Aurora - AWS Backup

`iac/aws/aws_backup.tf` で設定したAWS Backup Vault配下のリカバリポイント確認、および復元手順です。

### リカバリポイント一覧の確認

```powershell
$vaultName = "sandbox-aws-dev-aurora-vault"

aws backup list-recovery-points-by-backup-vault `
  --backup-vault-name $vaultName `
  --query 'RecoveryPoints[].[RecoveryPointArn,CreationDate,Status,BackupSizeInBytes]' `
  --output table
```

### バックアップジョブ実行状況の確認

```powershell
# 直近のバックアップジョブ(成否含む)
aws backup list-backup-jobs `
  --by-backup-vault-name sandbox-aws-dev-aurora-vault `
  --query 'BackupJobs[].[BackupJobId,State,CreationDate,CompletionDate,StatusMessage]' `
  --output table
```

### オンデマンドでバックアップを取得

```powershell
$accountId = (aws sts get-caller-identity | ConvertFrom-Json).Account
$clusterArn = "arn:aws:rds:ap-northeast-1:${accountId}:cluster:sandbox-aws-dev-db-cluster"

aws backup start-backup-job `
  --backup-vault-name sandbox-aws-dev-aurora-vault `
  --resource-arn $clusterArn `
  --iam-role-arn "arn:aws:iam::${accountId}:role/AWSBackup-sandbox-aws-dev-role"
```

### リカバリポイントから復元

復元は別クラスタ（別identifier）として作成されるため、既存クラスタへの上書きにはなりません。復元完了後、必要に応じてアプリの接続先（SSMパラメータの `DATABASE_URL`）を切り替えてください。

```powershell
$accountId = (aws sts get-caller-identity | ConvertFrom-Json).Account
$recoveryPointArn = "<list-recovery-points-by-backup-vaultで取得したARN>"
$roleArn = "arn:aws:iam::${accountId}:role/AWSBackup-sandbox-aws-dev-role"

# メタデータ(復元時の必須パラメータ)を取得
aws backup get-recovery-point-restore-metadata `
  --backup-vault-name sandbox-aws-dev-aurora-vault `
  --recovery-point-arn $recoveryPointArn

# 復元ジョブの開始(metadataはJSON文字列で渡す。DBClusterIdentifierを変更すること)
$metadata = @{
  DBClusterIdentifier = "sandbox-aws-dev-db-cluster-restored"
  Engine              = "aurora-postgresql"
  EngineMode          = "provisioned"
  VpcSecurityGroupIds = "<DB SG ID>"
  DBSubnetGroupName   = "sandbox-aws-dev"
} | ConvertTo-Json -Compress

aws backup start-restore-job `
  --recovery-point-arn $recoveryPointArn `
  --iam-role-arn $roleArn `
  --resource-type Aurora `
  --metadata $metadata
```

> 復元はクラスタのみ作成されるため、別途 `aws rds create-db-instance` でServerless v2インスタンスをアタッチする必要があります。

---

## DB接続 (踏み台経由)

各クラウドとも DB は VPC/VNet 内に Private IP/Endpoint で配置されており、ローカル PC から直接接続できません。踏み台を経由してポートフォワードで接続します。

### 概要

| クラウド | 踏み台種別 | 接続方式 | DB エンドポイント |
|---|---|---|---|
| AWS | EC2 + SSM Session Manager | SSM port forwarding (SSH 鍵不要) | Aurora cluster endpoint |
| Azure | Linux VM + SSH (Key Vault の公開鍵) | OpenSSH の `-L` 転送 | PostgreSQL Flexible Server FQDN |
| GCP | Compute Engine + IAP TCP forwarding | `gcloud compute ssh --tunnel-through-iap` の `-L` 転送 | Cloud SQL Private IP |

3 クラウドとも、最終的に `localhost:5432` を `psql` でアクセスする形に統一できます。

---

### AWS (Aurora Serverless v2)

接続情報を取得:

```powershell
# Aurora クラスタエンドポイントとマスター名
$DB_ENDPOINT = aws rds describe-db-clusters `
  --db-cluster-identifier sandbox-aws-dev-db-cluster `
  --query "DBClusters[0].Endpoint" --output text

$DB_USER = aws rds describe-db-clusters `
  --db-cluster-identifier sandbox-aws-dev-db-cluster `
  --query "DBClusters[0].MasterUsername" --output text

# DATABASE_URL を SSM Parameter Store (SecureString) から取得
$DATABASE_URL = aws ssm get-parameter `
  --name "/dev/connection_strings/sandbox-aws" `
  --with-decryption `
  --query "Parameter.Value" --output text

Write-Host "Endpoint: $DB_ENDPOINT"
Write-Host "User: $DB_USER"
Write-Host "URL: $DATABASE_URL"
```

Aurora が自動停止 (`auto-stop` で stopped) なら先に起動:

```powershell
aws rds start-db-cluster --db-cluster-identifier sandbox-aws-dev-db-cluster
# Available になるまで数分〜10分待機
```

踏み台 EC2 のインスタンス ID を取得して SSM ポートフォワード開始:

```powershell
$BASTION_ID = aws ec2 describe-instances `
  --filters "Name=tag:Name,Values=dev-bastion" "Name=instance-state-name,Values=running" `
  --query "Reservations[0].Instances[0].InstanceId" --output text

aws ssm start-session `
  --target $BASTION_ID `
  --document-name AWS-StartPortForwardingSessionToRemoteHost `
  --parameters "host=$DB_ENDPOINT,portNumber=5432,localPortNumber=5432"
# このウィンドウは開いたまま。Ctrl+C でセッション切断
```

別ウィンドウで `psql` で接続:

```powershell
# DATABASE_URL の URI 形式そのまま渡せる
psql "$DATABASE_URL"

# または個別パラメータで
psql -h localhost -p 5432 -U $DB_USER -d sandboxawsdevdb
```

---

### Azure (PostgreSQL Flexible Server)

接続情報を取得:

```powershell
# Flexible Server FQDN
$DB_FQDN = az postgres flexible-server show `
  --resource-group rg-sandbox-dev `
  --name sandbox-dev-db-server `
  --query "fullyQualifiedDomainName" --output tsv

# 管理者ユーザー名
$DB_USER = az postgres flexible-server show `
  --resource-group rg-sandbox-dev `
  --name sandbox-dev-db-server `
  --query "administratorLogin" --output tsv

# Bastion VM のパブリック IP
$BASTION_IP = az vm show -d `
  --resource-group rg-sandbox-dev `
  --name sandbox-dev-bastion-vm `
  --query "publicIps" --output tsv

# DB パスワード (Container Apps の env から取得 / Terraform output 経由でも可)
$DB_PASSWORD = az containerapp show `
  --resource-group rg-sandbox-dev `
  --name sandbox-dev-backend-app `
  --query "properties.template.containers[0].env[?name=='DATABASE_URL'].value | [0]" --output tsv
# DATABASE_URL から password だけ抜く場合は別途パース
```

> Flexible Server は private DNS で `*.private.postgres.database.azure.com` で名前解決される。ローカルからは `nslookup` で解決できないため、SSH トンネル先で `<FQDN>:5432` を指定する。

OpenSSH の `-L` でポートフォワード:

```powershell
ssh -i C:\path\to\private_key `
    -L 5432:${DB_FQDN}:5432 `
    azureuser@$BASTION_IP
# このセッションを開いたまま、別ウィンドウで psql
```

別ウィンドウで `psql`:

```powershell
psql -h localhost -p 5432 -U $DB_USER -d sandbox-dev-db
# パスワード入力プロンプト
```

> 公開鍵は Terraform で Key Vault から取得して VM に注入済み (`bastion.tf`)。対応する秘密鍵をローカル PC に保管してパス指定。

---

### GCP (Cloud SQL for PostgreSQL)

接続情報を取得:

```powershell
# Cloud SQL Private IP
$DB_IP = gcloud sql instances describe sandbox-gcp-dev-db `
  --format="value(ipAddresses[0].ipAddress)"

# ユーザー名
$DB_USER = "sandboxgcpdevdbadmin"

# DATABASE_URL を Secret Manager から取得
$DATABASE_URL = gcloud secrets versions access latest `
  --secret=sandbox-gcp-dev-database-url

Write-Host "DB IP: $DB_IP"
Write-Host "User: $DB_USER"
Write-Host "URL: $DATABASE_URL"
```

Cloud SQL が自動停止 (`activationPolicy = NEVER`) なら先に起動:

```powershell
gcloud sql instances patch sandbox-gcp-dev-db --activation-policy=ALWAYS
# RUNNABLE になるまで数分待機
```

Bastion 経由でポートフォワード (IAP TCP tunneling + SSH `-L`):

```powershell
gcloud compute ssh sandbox-gcp-dev-bastion `
  --zone=asia-northeast1-a `
  --tunnel-through-iap `
  -- -L "5432:${DB_IP}:5432" -N
# IAP TCP forwarding + SSH トンネル。 -N でリモートコマンド実行なし
# このウィンドウは開いたまま。Ctrl+C で切断
```

別ウィンドウで `psql`:

```powershell
# DATABASE_URL の host を localhost に置換して接続
$LOCAL_URL = $DATABASE_URL -replace [regex]::Escape($DB_IP), "localhost"
psql "$LOCAL_URL"

# または個別パラメータで
psql -h localhost -p 5432 -U $DB_USER -d sandboxgcpdevdb
```

> Bastion VM には `cloud-sql-proxy` と `postgresql-client` がプリインストール済み (`bastion.tf` の startup-script)。`gcloud compute ssh ... --tunnel-through-iap` で直接 SSH ログインし、`psql` を Bastion 上で実行することも可能。

---

## リソース削除

```powershell
# S3バケットを空にする (バケット名は実際のものに変更)
aws s3 rm s3://sandbox-aws-dev-artifact-xxxxx --recursive
aws s3 rm s3://sandbox-aws-dev-web-xxxxx --recursive

# ECRリポジトリを空にする
$repositoryName = "dev/sandbox-aws-backend"
$imageList = aws ecr list-images --repository-name $repositoryName --query "imageIds[*]" --output json | ConvertFrom-Json
foreach ($image in $imageList) {
    $imageDigest = $image.imageDigest
    $imageTag = $image.imageTag
    $imageId = @{}
    if ($imageDigest) { $imageId["imageDigest"] = $imageDigest }
    if ($imageTag) { $imageId["imageTag"] = $imageTag }
    aws ecr batch-delete-image --repository-name $repositoryName --image-ids (ConvertTo-Json @($imageId))
}
```

---

## Docker

```bash
docker build -t sandbox-backend -f ./Dockerfile .
docker run -p 3000:3000 -e LOG_LEVEL=error sandbox-backend:latest
```
