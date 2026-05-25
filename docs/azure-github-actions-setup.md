# Azure: GitHub Actions のセットアップ (初回のみ)

Azure 側のデプロイは GitHub Actions の `deploy-backend-azure.yaml` / `deploy-frontend-azure.yaml` から行いますが、 **Key Vault に `network_acls` を有効化している**ため、 ワークフローが Key Vault から secret を直接読み出す方式は使えません。 代わりに **GitHub Environments の Variables / Secrets** に値を登録します。

このドキュメントでは Terraform apply 完了後にワークフローを動かすまでの初期セットアップ手順をまとめます。

## 前提

- `iac/azure` で `terraform apply` 完了済み
- [GitHub CLI (`gh`)](https://cli.github.com/) インストール済み、 `gh auth login` 済み
- Azure CLI (`az`) インストール済み、 該当サブスクリプションで `az login` 済み
- 対象リポジトリの **Settings → Environments** を編集できる権限 (Admin)

## セットアップ手順

### 1. GitHub Environment "main" を作成

GitHub UI から `Settings → Environments → New environment` で **`main`** という名前の Environment を作成します。 (gh CLI には環境作成サブコマンドが無いため UI 操作必須)

任意で以下の保護ルールも設定可能 (本番化時に推奨):
- **Required reviewers**: deploy 実行に承認を必須化
- **Deployment branches**: deploy 可能なブランチを `main` に限定
- **Wait timer**: deploy 完了後の冷却期間

### 2. Terraform output から Variables / Secrets を一括登録

```powershell
cd iac/azure

# Variables (10個) を main Environment に登録
$vars = terraform output -json github_actions_variables | ConvertFrom-Json
$vars.PSObject.Properties | ForEach-Object {
  Write-Host "Setting variable: $($_.Name) = $($_.Value)" -ForegroundColor Cyan
  gh variable set $_.Name --env main --body $_.Value
}

# Secrets (3個) を main Environment に登録
$secrets = terraform output -json github_actions_secrets | ConvertFrom-Json
$secrets.PSObject.Properties | ForEach-Object {
  Write-Host "Setting secret: $($_.Name)" -ForegroundColor Yellow
  gh secret set $_.Name --env main --body $_.Value
}
```

### 3. OIDC 用 Secrets を repository-level に登録

OIDC 認証用の以下 3 つは全環境共通でよいため、 **Repository-level secrets** として登録します:

| Secret 名 | 取得元 |
|---|---|
| `AZURE_CLIENT_ID` | Key Vault の `github-AZURE-CLIENT-ID` |
| `AZURE_TENANT_ID` | Key Vault の `github-AZURE-TENANT-ID` |
| `AZURE_SUBSCRIPTION_ID` | Key Vault の `github-AZURE-SUBSCRIPTION-ID` |

```powershell
# Key Vault 名を取得 (ローカル PC の IP が KV の ip_rules に許可されている前提)
$KV = az keyvault list --query "[?ends_with(name, 'main')].name" -o tsv

# 値を取得して repository secret に登録
$cid = az keyvault secret show --vault-name $KV --name "github-AZURE-CLIENT-ID"       --query "value" -o tsv
$tid = az keyvault secret show --vault-name $KV --name "github-AZURE-TENANT-ID"       --query "value" -o tsv
$sid = az keyvault secret show --vault-name $KV --name "github-AZURE-SUBSCRIPTION-ID" --query "value" -o tsv

gh secret set AZURE_CLIENT_ID       --body $cid
gh secret set AZURE_TENANT_ID       --body $tid
gh secret set AZURE_SUBSCRIPTION_ID --body $sid
```

### 4. 登録内容を確認

```powershell
# main Environment の Variables (10 個あるはず)
gh variable list --env main

# main Environment の Secrets (3 個あるはず: VITE_AUTH0_*)
gh secret list --env main

# Repository-level Secrets (AZURE_CLIENT_ID / TENANT_ID / SUBSCRIPTION_ID 等)
gh secret list
```

### 5. ワークフロー実行

```powershell
# バックエンド
gh workflow run deploy-backend-azure.yaml --ref main --field environment=main

# フロントエンド
gh workflow run deploy-frontend-azure.yaml --ref main --field environment=main
```

ブラウザで `Actions` タブから進行状況を確認できます。

## 各 Variables / Secrets の対応表

### Repository Variables (vars)

| 変数名 | 例 |
|---|---|
| (なし — 本テンプレでは Environment-level のみ使用) | |

### Repository Secrets (secrets)

| シークレット名 | 用途 |
|---|---|
| `AZURE_CLIENT_ID` | OIDC ログイン (Azure AD app) |
| `AZURE_TENANT_ID` | OIDC ログイン (テナント ID) |
| `AZURE_SUBSCRIPTION_ID` | OIDC ログイン (サブスクリプション ID) |

### Environment Variables (vars, `main` 環境)

| 変数名 | 取得元 (terraform output) |
|---|---|
| `AZURE_RESOURCE_GROUP` | `azurerm_resource_group.rg.name` |
| `AZURE_ACR_NAME` | `azurerm_container_registry.acr.name` |
| `AZURE_BACKEND_IMAGE_NAME` | `${app-name}-${env}-backend` |
| `AZURE_BACKEND_WORKING_DIRECTORY` | `/${var.backend-src-root}` |
| `AZURE_BACKEND_CONTAINER_APP_NAME` | `azurerm_container_app.app.name` |
| `AZURE_FRONTEND_WORKING_DIRECTORY` | `/${var.frontend-src-root}` |
| `AZURE_FRONTEND_STORAGE_ACCOUNT_NAME` | `azurerm_storage_account.web.name` |
| `AZURE_FRONTDOOR_PROFILE_NAME` | `azurerm_cdn_frontdoor_profile.cdn.name` |
| `AZURE_FRONTDOOR_ENDPOINT_NAME` | `azurerm_cdn_frontdoor_endpoint.cdn.name` |
| `VITE_API_BASE_URL` | `https://${frontdoor.host_name}` |

### Environment Secrets (secrets, `main` 環境)

| シークレット名 | 用途 |
|---|---|
| `VITE_AUTH0_CLIENT_ID` | Vite ビルド時に SPA に埋め込む Auth0 client_id |
| `VITE_AUTH0_DOMAIN` | 同 Auth0 domain |
| `VITE_AUTH0_AUDIENCE` | 同 Auth0 audience |

## トラブルシューティング

### `AADSTS700213: No matching federated identity record found for presented assertion subject 'repo:...:environment:dev'`

**原因**: ワークフローの `inputs.environment` で `dev` 等を選んだが、 federated identity credential の subject は `environment:main` 形式しか登録されていない。

**対処**: ワークフロー実行時に **必ず `environment=main` を選択**する。 別の環境を増やす場合は本ドキュメント末尾の「マルチ環境への拡張」を参照。

### env 値が空 (`ACR_NAME:` 等が空欄になる)

**原因**: GitHub Environment "main" に Variables / Secrets が登録されていない、 または間違って repository-level に登録した、 または Secret として登録したが workflow が `vars.X` で参照している、 等。

**対処**:
```powershell
gh variable list --env main   # 10 個あるはず
gh secret list --env main     # 3 個あるはず
```
不足しているものがあれば 2. の一括登録スクリプトを再実行 (上書きされるだけなので安全)。

### `AADSTS700016: Application with identifier '***' was not found in the directory '既定のディレクトリ'`

**原因**: GitHub Actions secrets の `AZURE_CLIENT_ID` (アプリ登録 ID) が、 認証先テナント (`AZURE_TENANT_ID`) に存在しない。 古いテナントのアプリ ID を指している可能性が高い。

**対処**: 3. の手順で Key Vault の `github-AZURE-*` から最新値を取得して上書き登録。

### Key Vault から secret 取得が `403 Forbidden`

**原因**: Key Vault の `network_acls` で開発者 PC の IP が未許可。

**対処**: `iac/azure/terraform.tfvars` の `local-pc-ip-addresses` に現在の PC の IP を追加 → `terraform apply`。 IP は `curl ifconfig.me` 等で確認可能。

## マルチ環境への拡張 (staging / prod 等)

将来 `staging` や `prod` を追加するときの手順:

### 1. Terraform 側で federated credential を増やす

`iac/azure/service-principal.tf` の `azuread_application_federated_identity_credential.github_actions` を `for_each` で複数化:

```hcl
locals {
  github_environments = ["main", "staging", "prod"]
}

resource "azuread_application_federated_identity_credential" "github_actions" {
  for_each       = toset(local.github_environments)
  application_id = azuread_application_registration.github_actions.id
  display_name   = "${var.app-name}-${var.environment}-github-actions-${each.key}"
  description    = "Deployments for ${var.github-repository-name} via GitHub Environment '${each.key}'"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github-repository-name}:environment:${each.key}"
}
```

`terraform apply` で対応するクレデンシャル が作成される。

### 2. ワークフローの選択肢を追加

`.github/workflows/deploy-{backend,frontend}-azure.yaml` の `inputs.environment.options` に追加:

```yaml
options:
  - main
  - staging
  - prod
```

### 3. GitHub で対応する Environment を作成

`Settings → Environments → New environment` で `staging` / `prod` を作成し、 それぞれに Variables / Secrets を登録 (各環境ごとに別の terraform state があり、 別の値が出力される想定)。

### 4. 環境別の保護ルール (推奨)

| 環境 | 推奨設定 |
|---|---|
| `main` | なし (dev 用、 任意ブランチから deploy 可) |
| `staging` | Required reviewers なし、 `develop` ブランチのみ |
| `prod` | **Required reviewers 必須** + `main` ブランチのみ + Wait timer 5分 |
