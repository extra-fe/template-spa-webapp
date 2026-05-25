# Auth0アプリケーション (SPA): フロントエンドからの認証フロー用クライアント
# - コールバック / ログアウト / Web Origin に LB の公開 URL を許可
resource "auth0_client" "app" {
  allowed_logout_urls = [
    local.public_url,
  ]
  app_type = "spa"
  callbacks = [
    local.public_url,
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
    local.public_url,
  ]

  jwt_configuration {
    alg = "RS256"
  }
}

# Auth0 API (Resource Server): バックエンドが検証するアクセストークンの audience を定義
resource "auth0_resource_server" "audience" {
  name        = "${var.app-name}-${var.environment}-gcp-audience"
  identifier  = local.public_url
  signing_alg = "RS256"
}
