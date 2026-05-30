# IaC CI/CD セットアップガイド (Terraform plan/apply)

GitHub Actions で `terraform plan` (PR 時) / `terraform apply` (main マージ時) を動かすための
初回セットアップ手順と、使用する GitHub Variables / Secrets の一覧。

自動化 (ワークフロー本体) の仕様は `docs/iac-spec.md` の「6. CI/CD」節を参照。

---

## 前提

- `iac/<cloud>/bootstrap/` を apply 済み (state backend が存在する)
- `iac/<cloud>/github_actions_terraform.tf` (OIDC 認証リソース) を apply 済み
- GitHub CLI (`gh`) インストール済み、`gh auth login` 済み
- 対象リポジトリの Settings を編集できる Admin 権限

---

## GitHub Variables / Secrets 一覧

### State Backend 変数 (`TF_STATE_*`)

`iac/<cloud>/bootstrap/` を apply 後に登録する。`terraform output backend_config_hint` で確認できる。

| 変数名 | 登録種別 | 説明 | 値の例 |
|---|---|---|---|
| `TF_STATE_BUCKET_AWS` | Variable | AWS state 用 S3 バケット名 | `sandbox-aws-dev-tfstate-123456789012` |
| `TF_STATE_KEY_AWS` | Variable | S3 オブジェクトキー | `aws/terraform.tfstate` |
| `TF_STATE_REGION_AWS` | Variable | state バケットのリージョン | `ap-northeast-1` |
| `TF_STATE_BUCKET_GCP` | Variable | GCP state 用 GCS バケット名 | `sandbox-gcp-dev-tfstate-my-project-id` |
| `TF_STATE_PREFIX_GCP` | Variable | GCS オブジェクトプレフィックス | `gcp/terraform.tfstate` |
| `TF_STATE_RG_AZURE` | Variable | Azure state 用リソースグループ名 | `sandbox-dev-tfstate-rg` |
| `TF_STATE_SA_AZURE` | Variable | Azure state 用 Storage Account 名 | `sandboxdevABCDEFtfstate` |
| `TF_STATE_CONTAINER_AZURE` | Variable | Azure Blob コンテナ名 | `tfstate` |
| `TF_STATE_KEY_AZURE` | Variable | Azure Blob キー | `azure/terraform.tfstate` |

### OIDC 認証変数 (`TF_PLAN_*` / `TF_APPLY_*`)

`iac/<cloud>/github_actions_terraform.tf` を apply 後に登録する。`terraform output github_actions_terraform` で確認できる。

| 変数名 | 登録種別 | 説明 | 値の例 |
|---|---|---|---|
| `TF_PLAN_ROLE_ARN_AWS` | Variable | AWS plan 用 IAM Role ARN | `arn:aws:iam::123456789012:role/sandbox-aws-dev-terraform-plan` |
| `TF_APPLY_ROLE_ARN_AWS` | Variable | AWS apply 用 IAM Role ARN | `arn:aws:iam::123456789012:role/sandbox-aws-dev-terraform-apply` |
| `AWS_REGION` | Variable | AWS リージョン | `ap-northeast-1` |
| `TF_PLAN_SA_GCP` | Variable | GCP plan 用 SA メール | `sandbox-gcp-dev-tf-plan@my-project.iam.gserviceaccount.com` |
| `TF_APPLY_SA_GCP` | Variable | GCP apply 用 SA メール | `sandbox-gcp-dev-tf-apply@my-project.iam.gserviceaccount.com` |
| `TF_WIF_PROVIDER_GCP` | Variable | GCP Workload Identity Provider リソース名 | `projects/123/locations/global/workloadIdentityPools/sandbox-gcp-dev-gh/providers/github` |
| `TF_PLAN_CLIENT_ID_AZURE` | Variable | Azure plan 用 App Registration Client ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `TF_APPLY_CLIENT_ID_AZURE` | Variable | Azure apply 用 App Registration Client ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `AZURE_TENANT_ID` | **Secret** | Azure テナント ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `AZURE_SUBSCRIPTION_ID` | **Secret** | Azure サブスクリプション ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |

> **Variable vs Secret の使い分け**
> - Variable: 機密でない値。ワークフローログにも表示される。
> - Secret: テナント ID・サブスクリプション ID など、漏洩するとなりすまし・フィッシングに悪用されうる値。

---

## セットアップ手順

### 1. State Backend 変数を登録

`iac/<cloud>/bootstrap/` を apply した後に実行する。

```powershell
# AWS
cd iac/aws/bootstrap
$out = terraform output -json backend_config_hint | ConvertFrom-Json
gh variable set TF_STATE_BUCKET_AWS --body $out.bucket
gh variable set TF_STATE_KEY_AWS    --body $out.key
gh variable set TF_STATE_REGION_AWS --body $out.region

# GCP
cd iac/gcp/bootstrap
$out = terraform output -json backend_config_hint | ConvertFrom-Json
gh variable set TF_STATE_BUCKET_GCP --body $out.bucket
gh variable set TF_STATE_PREFIX_GCP --body $out.prefix

# Azure
cd iac/azure/bootstrap
$out = terraform output -json backend_config_hint | ConvertFrom-Json
gh variable set TF_STATE_RG_AZURE        --body $out.resource_group_name
gh variable set TF_STATE_SA_AZURE        --body $out.storage_account_name
gh variable set TF_STATE_CONTAINER_AZURE --body $out.container_name
gh variable set TF_STATE_KEY_AZURE       --body $out.key
```

### 2. OIDC 認証変数を登録

`iac/<cloud>/github_actions_terraform.tf` を apply した後に実行する。

```powershell
# AWS
cd iac/aws
$out = terraform output -json github_actions_terraform | ConvertFrom-Json
gh variable set TF_PLAN_ROLE_ARN_AWS  --body $out.TF_PLAN_ROLE_ARN_AWS
gh variable set TF_APPLY_ROLE_ARN_AWS --body $out.TF_APPLY_ROLE_ARN_AWS
gh variable set AWS_REGION            --body $out.AWS_REGION

# GCP
cd iac/gcp
$out = terraform output -json github_actions_terraform | ConvertFrom-Json
gh variable set TF_PLAN_SA_GCP      --body $out.TF_PLAN_SA_GCP
gh variable set TF_APPLY_SA_GCP     --body $out.TF_APPLY_SA_GCP
gh variable set TF_WIF_PROVIDER_GCP --body $out.TF_WIF_PROVIDER_GCP

# Azure (sensitive output のため -json 経由で取得)
cd iac/azure
$raw = terraform output -json github_actions_terraform
$out = $raw | ConvertFrom-Json
gh variable set TF_PLAN_CLIENT_ID_AZURE  --body $out.TF_PLAN_CLIENT_ID_AZURE
gh variable set TF_APPLY_CLIENT_ID_AZURE --body $out.TF_APPLY_CLIENT_ID_AZURE
gh secret  set AZURE_TENANT_ID           --body $out.AZURE_TENANT_ID
gh secret  set AZURE_SUBSCRIPTION_ID     --body $out.AZURE_SUBSCRIPTION_ID
```

### 3. GitHub Environment "iac-apply" を作成

GitHub UI から操作する (`gh` CLI では Environment 作成ができないため)。

1. リポジトリ → **Settings → Environments → New environment**
2. 名前: **`iac-apply`**
3. **Protection rules** で以下を設定:
   - **Required reviewers**: apply 実行前に承認を必須化 (本番適用の誤操作防止)
   - **Deployment branches**: `main` ブランチのみに限定

> Environment を作成しないと apply ワークフローが OIDC 認証で失敗する。
> (`token.actions.githubusercontent.com:sub` が `environment:iac-apply` にならないため)

### 4. 登録内容を確認

```powershell
# Variables 一覧 (TF_* が揃っているか確認)
gh variable list

# Secrets 一覧
gh secret list
```

---

## 変数の仕組み

ワークフロー (`.github/workflows/ci-iac.yaml`) は以下の流れで変数を利用する。

```
GitHub Variables/Secrets
        │
        ▼
terraform init -backend-config   ← TF_STATE_* でどの state を参照するか決まる
        │
        ▼
GitHub OIDC → AWS/GCP/Azure      ← TF_PLAN_*/TF_APPLY_* でどの権限でアクセスするか決まる
        │
        ▼
terraform plan / apply
```

| フェーズ | 使う変数 | 役割 |
|---|---|---|
| `terraform init` | `TF_STATE_*` | -backend-config に渡し、リモート state の場所を指定 |
| OIDC 認証 (plan) | `TF_PLAN_*` | PR ジョブが AssumeRoleWithWebIdentity / impersonate |
| OIDC 認証 (apply) | `TF_APPLY_*` | iac-apply Environment 承認後のジョブのみ利用可 |

### plan と apply で ID を分けている理由

| ロール | 権限 | 信頼する OIDC subject |
|---|---|---|
| plan | 読み取り専用 (ReadOnly / viewer / Reader) | `pull_request` / `ref:refs/heads/main` |
| apply | 全操作 (AdministratorAccess / owner / Owner) | `environment:iac-apply` のみ |

apply ロールは GitHub Environment の **必須レビュアー承認** を経ないと取得できない subject
(`environment:iac-apply`) からしか AssumeRole できない。これにより、`terraform apply`
の実行には必ず人間の承認が必要になる。

---

## 関連ドキュメント

- `docs/iac-spec.md` — IaC 全体仕様・CI/CD フロー詳細
- `docs/azure-github-actions-setup.md` — Azure デプロイ用 OIDC の初回セットアップ
- `iac/<cloud>/bootstrap/README.md` — 各クラウドの state backend 作成手順
