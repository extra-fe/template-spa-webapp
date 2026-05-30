# AWS Terraform state backend ブートストラップ

`iac/aws` の Terraform state を格納するリモート backend (S3 バケット) を作成する。
リモート backend を作るための「土台」なので、このモジュール自身はローカル state で動く
(`backend` ブロックを持たない)。**初回 1 回だけ手動適用する。**

ロックは S3 ネイティブロックファイル (`use_lockfile = true`) を使うため DynamoDB は不要。

## 作成されるもの

- state 専用 S3 バケット `sandbox-aws-dev-tfstate-<AWS_ACCOUNT_ID>`
  - バージョニング有効 / SSE-S3 暗号化 / パブリックアクセス全ブロック / HTTPS 強制

## 手順

### 1. state バケットを作成 (初回のみ)

```bash
cd iac/aws/bootstrap
terraform init
terraform apply
terraform output backend_config_hint   # bucket / key / region を控える
```

### 2. 親 (iac/aws) のローカル state をリモートへ移行 (初回のみ)

```powershell
cd iac/aws
cp backend.hcl.example backend.hcl      # 1. の output の値で埋める
terraform init "-backend-config=backend.hcl" -migrate-state
# "Do you want to copy existing state?" → yes
```

`-migrate-state` で既存のローカル `terraform.tfstate` が S3 へコピーされる。移行後は
ローカルの `terraform.tfstate*` は不要 (gitignore 済み)。

> PowerShell では `-backend-config=...` をクォートで囲む必要がある (`=` を含む引数が
> 分割されるため)。

### 3. GitHub Variables に登録 (CI 用)

PR の plan / apply ワークフローが backend 設定を参照するため、リポジトリの Variables に登録する。

```powershell
cd iac/aws/bootstrap
$out = terraform output -json backend_config_hint | ConvertFrom-Json
gh variable set TF_STATE_BUCKET_AWS --body $out.bucket
gh variable set TF_STATE_KEY_AWS    --body $out.key
gh variable set TF_STATE_REGION_AWS --body $out.region
```

確認:
```powershell
gh variable list
```

## 注意

- このモジュールの state (`bootstrap/terraform.tfstate`) はローカルに残る。バケット定義は
  ほぼ不変なので通常は再 apply 不要。チームで共有する場合は別途リモート化を検討する。
- バケットは `force_destroy` を付けていない。誤削除防止のため、破棄が必要な場合は手動で空にする。
