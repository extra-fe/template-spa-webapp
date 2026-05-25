resource "azuread_application_registration" "github_actions" {
  display_name     = "${var.app-name}-${var.environment}-github-actions-${var.target-branch}"
  description      = "for GitHub Actions"
  sign_in_audience = "AzureADMyOrg"
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application_registration.github_actions.client_id
}

resource "azurerm_role_assignment" "github_actions_blob_contributor" {
  scope                = azurerm_storage_account.web.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

resource "azurerm_role_assignment" "github_actions_cdn_profile_contributor" {
  scope                = azurerm_cdn_frontdoor_profile.cdn.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}


resource "azuread_application_federated_identity_credential" "github_actions" {
  application_id = azuread_application_registration.github_actions.id
  display_name   = "${var.app-name}-${var.environment}-github-actions-${var.target-branch}"
  description    = "Deployments for ${var.github-repository-name} via GitHub Environment '${var.target-branch}'"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  # GitHub Actions の job に environment: ${{ inputs.environment }} を指定すると、
  # OIDC token の subject claim が `repo:OWNER/REPO:environment:ENV_NAME` 形式になる。
  # 本テンプレートでは main ブランチ用の env 1 つだけを用意する方針なので、
  # var.target-branch (= "main") を環境名として使用する。
  # 別環境を追加する場合は azuread_application_federated_identity_credential を for_each 等で増やす。
  subject = "repo:${var.github-repository-name}:environment:${var.target-branch}"
}

resource "azurerm_role_assignment" "github_actions_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.github_actions.object_id
}

resource "azurerm_role_assignment" "github_actions_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azuread_service_principal.github_actions.object_id
}

resource "azurerm_role_assignment" "github_actions_container_app_contributor" {
  scope                = azurerm_container_app.app.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}
