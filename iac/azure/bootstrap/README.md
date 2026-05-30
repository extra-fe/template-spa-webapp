# Azure Terraform state backend ブートストラップ

`iac/azure` の Terraform state を格納するリモート backend (Storage Account + Blob コンテナ)
を作成する。リモート backend を作るための「土台」なので、このモジュール自身はローカル state
で動く (`backend` ブロックを持たない)。**初回 1 回だけ手動適用する。**

azurerm backend は Blob のリース機構によるロックを内蔵するため、別途ロック資源は不要。

## 作成されるもの

- state 用リソースグループ `sandbox-dev-tfstate-rg`
- state 用 Storage Account `sandboxdev<RANDOM>tfstate`
  - Blob バージョニング有効 / TLS1.2 強制 / HTTPS 強制 / 公開禁止
- Blob コンテナ `tfstate`

## 手順

### 1. state ストレージを作成 (初回のみ)

```powershell
cd iac/azure/bootstrap
terraform init
terraform apply -var="azure-subscription-id=$(az account show --query id -o tsv)"
terraform output backend_config_hint   # 各値を控える
```

### 2. 親 (iac/azure) のローカル state をリモートへ移行 (初回のみ)

```powershell
cd iac/azure
cp backend.hcl.example backend.hcl      # 1. の output の値で埋める
terraform init "-backend-config=backend.hcl" -migrate-state
```

> PowerShell では `-backend-config=...` をクォートで囲む必要がある (`=` を含む引数が
> 分割されるため)。

### 3. GitHub Variables に登録 (CI 用)

```powershell
cd iac/azure/bootstrap
$out = terraform output -json backend_config_hint | ConvertFrom-Json
gh variable set TF_STATE_RG_AZURE        --body $out.resource_group_name
gh variable set TF_STATE_SA_AZURE        --body $out.storage_account_name
gh variable set TF_STATE_CONTAINER_AZURE --body $out.container_name
gh variable set TF_STATE_KEY_AZURE       --body $out.key
```

確認:
```powershell
gh variable list
```

## 注意

- このモジュールの state (`bootstrap/terraform.tfstate`) はローカルに残る。
- Storage Account は誤削除防止のため、破棄が必要な場合は手動でコンテナを空にする。
