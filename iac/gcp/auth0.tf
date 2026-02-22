resource "auth0_client" "app" {
  allowed_logout_urls = [
    "http://${google_compute_global_address.lb-ip.address}"
  ]
  app_type = "spa"
  callbacks = [
    "http://${google_compute_global_address.lb-ip.address}"
  ]
  cross_origin_auth = false
  grant_types = [
    "authorization_code",
    "implicit",
    "refresh_token",
  ]
  name            = "${var.app-name}-${var.environment}-gcp-idp"
  oidc_conformant = true
  web_origins = [
    "http://${google_compute_global_address.lb-ip.address}"
  ]

  jwt_configuration {
    alg = "RS256"
  }
}

resource "auth0_resource_server" "audience" {
  name        = "${var.app-name}-${var.environment}-gcp-audience"
  identifier  = "http://${google_compute_global_address.lb-ip.address}"
  signing_alg = "RS256"
}
