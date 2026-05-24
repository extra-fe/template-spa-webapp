# CloudFront レスポンスヘッダポリシー: ブラウザ側セキュリティヘッダをCloudFrontで一括付与する
# - SPA配信用 (default / /index.html ビヘイビア) と API用 (/api/*) で別ポリシー
# - APIレスポンスにはCSP/Permissions-Policy不要のため軽量版を適用

# CSP: 1行のヘッダ値として組み立てる
# - connect-src / frame-src は Auth0 silent auth iframe・トークン取得通信を許可
# - style-src は React/UIライブラリの inline style 互換性のため 'unsafe-inline' を許容
# - img-src は Auth0 ユーザープロフィール画像 (gravatar 等) のため https: 全許可
locals {
  csp_directives = join("; ", [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: https:",
    "font-src 'self' data:",
    "connect-src 'self' https://${var.auth0_domain}",
    "frame-src https://${var.auth0_domain}",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "upgrade-insecure-requests",
  ])
}

# SPA配信用ポリシー: default_cache_behavior と /index.html ビヘイビアに適用
resource "aws_cloudfront_response_headers_policy" "spa" {
  name = "${var.app-name}-${var.environment}-spa-security-headers"

  security_headers_config {
    # HSTS: 1年・サブドメイン含む。*.cloudfront.net は preload 申請不可のため preload は無効
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = false
      override                   = true
    }
    content_type_options {
      override = true
    }
    # clickjacking 対策。CSP frame-ancestors 'none' と二重で防御
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    # OWASP推奨: 旧仕様の X-XSS-Protection は無効化 (= "0")
    xss_protection {
      protection = false
      override   = true
    }
    content_security_policy {
      content_security_policy = local.csp_directives
      override                = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=(), interest-cohort=()"
      override = true
    }
  }
}

# API用ポリシー: /api/* ビヘイビアに適用。CSP/Permissions-Policy はAPIレスポンスでは不要
resource "aws_cloudfront_response_headers_policy" "api" {
  name = "${var.app-name}-${var.environment}-api-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = false
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "no-referrer"
      override        = true
    }
    xss_protection {
      protection = false
      override   = true
    }
  }
}
