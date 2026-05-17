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
| VPC CIDRの範囲内（例: `172.16.x.x`） | VPCエンドポイント経由 ✅ |
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
