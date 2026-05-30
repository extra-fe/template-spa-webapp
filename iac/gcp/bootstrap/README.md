# GCP Terraform state backend ブートストラップ

`iac/gcp` の Terraform state を格納するリモート backend (GCS バケット) を作成する。
リモート backend を作るための「土台」なので、このモジュール自身はローカル state で動く
(`backend` ブロックを持たない)。**初回 1 回だけ手動適用する。**

GCS backend はオブジェクトの世代管理によるロックを内蔵するため、別途ロック資源は不要。

## 作成されるもの

- state 専用 GCS バケット `sandbox-gcp-dev-tfstate-<GCP_PROJECT_ID>`
  - バージョニング有効 / 一様バケットレベルアクセス / 公開禁止 (enforced)

## 手順

### 1. state バケットを作成 (初回のみ)

```powershell
cd iac/gcp/bootstrap
terraform init
terraform apply -var="gcp-project-id=$(gcloud config get-value project)"
terraform output backend_config_hint   # bucket / prefix を控える
```

### 2. 親 (iac/gcp) のローカル state をリモートへ移行 (初回のみ)

```powershell
cd iac/gcp
cp backend.hcl.example backend.hcl      # 1. の output の値で埋める
terraform init "-backend-config=backend.hcl" -migrate-state
```

> PowerShell では `-backend-config=...` をクォートで囲む必要がある (`=` を含む引数が
> 分割されるため)。

### 3. GitHub Variables に登録 (CI 用)

```powershell
cd iac/gcp/bootstrap
$out = terraform output -json backend_config_hint | ConvertFrom-Json
gh variable set TF_STATE_BUCKET_GCP --body $out.bucket
gh variable set TF_STATE_PREFIX_GCP --body $out.prefix
```

確認:
```powershell
gh variable list
```

## 注意

- このモジュールの state (`bootstrap/terraform.tfstate`) はローカルに残る。
- バケットは `force_destroy = false`。破棄が必要な場合は手動でオブジェクトを空にする。
