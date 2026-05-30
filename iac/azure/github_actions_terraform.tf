# GitHub Actions 用 OIDC (terraform plan / apply)
#
# 既存のデプロイ用 SP (service-principal.tf) とは別に、terraform 専用の
# App Registration / Service Principal を plan / apply それぞれ作成する。
#
# plan SP:  Reader ロール → PR や workflow_dispatch から利用可。
# apply SP: Owner ロール → GitHub Environment "iac-apply" 承認後のみ利用可。
#           Owner が必要な理由: terraform apply は azurerm_role_assignment を作成するため
#           Microsoft.Authorization/roleAssignments/write 権限が必要。
#
# 各 SP には Federated Identity Credential を複数付与する:
#   plan  → pull_request イベント用 + workflow_dispatch (refs/heads/main) 用
#   apply → iac-apply Environment 用
#
# 登録が必要な GitHub Variables / Secrets は terraform output github_actions_terraform で確認。

# ---------- plan 用 App Registration / SP ----------

resource "azuread_application_registration" "terraform_plan" {
  display_name     = "${var.app-name}-${var.environment}-terraform-plan"
  description      = "GitHub Actions terraform plan 用 (Reader)"
  sign_in_audience = "AzureADMyOrg"
}

resource "azuread_service_principal" "terraform_plan" {
  client_id = azuread_application_registration.terraform_plan.client_id
}

# PR イベント時の Federated Credential
# subject = repo:OWNER/REPO:pull_request
resource "azuread_application_federated_identity_credential" "terraform_plan_pr" {
  application_id = azuread_application_registration.terraform_plan.id
  display_name   = "${var.app-name}-${var.environment}-terraform-plan-pr"
  description    = "terraform plan on pull_request"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github-repository-name}:pull_request"
}

# workflow_dispatch 時の Federated Credential (main ブランチから手動実行)
# subject = repo:OWNER/REPO:ref:refs/heads/main
resource "azuread_application_federated_identity_credential" "terraform_plan_dispatch" {
  application_id = azuread_application_registration.terraform_plan.id
  display_name   = "${var.app-name}-${var.environment}-terraform-plan-dispatch"
  description    = "terraform plan on workflow_dispatch (main)"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github-repository-name}:ref:refs/heads/main"
}

# サブスクリプション全体への Reader ロール
resource "azurerm_role_assignment" "terraform_plan_reader" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.terraform_plan.object_id
}

# ---------- apply 用 App Registration / SP ----------

resource "azuread_application_registration" "terraform_apply" {
  display_name     = "${var.app-name}-${var.environment}-terraform-apply"
  description      = "GitHub Actions terraform apply 用 (Owner / iac-apply Environment のみ)"
  sign_in_audience = "AzureADMyOrg"
}

resource "azuread_service_principal" "terraform_apply" {
  client_id = azuread_application_registration.terraform_apply.client_id
}

# GitHub Environment "iac-apply" が active なジョブのみ利用可能
# subject = repo:OWNER/REPO:environment:iac-apply
resource "azuread_application_federated_identity_credential" "terraform_apply" {
  application_id = azuread_application_registration.terraform_apply.id
  display_name   = "${var.app-name}-${var.environment}-terraform-apply"
  description    = "terraform apply on iac-apply environment"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github-repository-name}:environment:iac-apply"
}

# サブスクリプション全体への Owner ロール
# terraform apply は azurerm_role_assignment / azuread_* リソースを管理するため
# Owner が必要 (Contributor では Microsoft.Authorization/roleAssignments/write が欠ける)。
resource "azurerm_role_assignment" "terraform_apply_owner" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Owner"
  principal_id         = azuread_service_principal.terraform_apply.object_id
}

# ---------- state backend へのアクセス権 ----------
#
# use_azuread_auth = true (backend.tf) で AAD 認証を使うため、
# plan SP には Blob 読み取り / apply SP には Blob 読み書きが必要。
# listKeys 権限は不要になる。
# tfstate RG 名は既存変数から計算できるため新規変数は不要。

locals {
  tfstate_rg_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.app-name}-${var.environment}-tfstate-rg"
}

resource "azurerm_role_assignment" "terraform_plan_tfstate_reader" {
  scope                = local.tfstate_rg_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azuread_service_principal.terraform_plan.object_id
}

resource "azurerm_role_assignment" "terraform_apply_tfstate_contributor" {
  scope                = local.tfstate_rg_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.terraform_apply.object_id
}

# ---------- outputs ----------

output "github_actions_terraform" {
  description = "PR3 ワークフローに設定する GitHub Variables / Secrets の値 (gh variable/secret set で登録)"
  sensitive   = true
  value = {
    TF_PLAN_CLIENT_ID_AZURE  = azuread_application_registration.terraform_plan.client_id
    TF_APPLY_CLIENT_ID_AZURE = azuread_application_registration.terraform_apply.client_id
    AZURE_TENANT_ID          = data.azurerm_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID    = data.azurerm_client_config.current.subscription_id
  }
}
