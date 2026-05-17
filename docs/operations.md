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
| パブリックIP | NAT Gateway経由 ❌ |

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
