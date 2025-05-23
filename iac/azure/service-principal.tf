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

resource "azurerm_role_assignment" "github_actions_key_vault_reader" {
  scope                = azurerm_key_vault.vault.id
  role_definition_name = "Key Vault Reader"
  principal_id         = azuread_service_principal.github_actions.object_id
}


resource "azurerm_role_assignment" "github_actions_key_vault_secrets_user" {
  scope                = azurerm_key_vault.vault.id
  role_definition_name = "Key Vault Secrets User"
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
  description    = "Deployments for ${var.github-repository-name} ${var.target-branch}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github-repository-name}:ref:refs/heads/${var.target-branch}"
}
