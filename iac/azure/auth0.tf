resource "auth0_client" "app" {
  allowed_logout_urls = [
    "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
  ]
  app_type = "spa"
  callbacks = [
    "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
  ]
  cross_origin_auth = false
  grant_types = [
    "authorization_code",
    "implicit",
    "refresh_token",
  ]
  name            = "${var.app-name}-${var.environment}-azure-idp"
  oidc_conformant = true
  web_origins = [
    "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
  ]

  jwt_configuration {
    alg = "RS256"
  }
}

resource "auth0_resource_server" "audience" {
  name        = "${var.app-name}-${var.environment}-azure-audience"
  identifier  = "https://${azurerm_cdn_frontdoor_endpoint.cdn.host_name}"
  signing_alg = "RS256"
}
