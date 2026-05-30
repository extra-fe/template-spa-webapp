# External Application Load Balancer + Cloud CDN
# AWS の CloudFront + ALB + VPC Origin に相当
#
# 構成:
#   ユーザ
#     ↓
#   Global Forwarding Rule (HTTPS 443 / HTTP 80→HTTPSリダイレクト)
#     ↓
#   Target HTTPS Proxy + Managed SSL Cert
#     ↓
#   URL Map (path matcher)
#     ├── /api/*       → Backend Service (Serverless NEG → Cloud Run)
#     └── default      → Backend Bucket  (GCS, Cloud CDN 有効)
#                         └── SPAルーティング: notFoundPage = index.html
#
# Cloud Armor: HTTPS Backend Service / Backend Bucket にアタッチ
#
# AWS の /index.html 個別ビヘイビア (no-cache) に相当する仕組みは、
# フロントエンドデプロイ時に index.html へ Cache-Control: no-store, no-cache を付与する運用で実現
# (CloudFront 側と同じ手法)

# グローバル静的 IP: LB のフロントエンド IP
resource "google_compute_global_address" "lb_ip" {
  name = "${var.app-name}-${var.environment}-lb-ip"

  depends_on = [time_sleep.wait_for_apis]
}

# Serverless NEG: Cloud Run サービスを LB のバックエンドとして公開する
# Cloud Run サービスの実体は cloud_run.tf で定義
resource "google_compute_region_network_endpoint_group" "backend_neg" {
  name                  = "${var.app-name}-${var.environment}-backend-neg"
  region                = var.gcp-region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.backend.name
  }
}

# Backend Service: Cloud Run NEG をぶら下げる
# AWS の ALB + Target Group + Cloud Armor (WAF) の組み合わせに相当
resource "google_compute_backend_service" "backend" {
  name                  = "${var.app-name}-${var.environment}-backend"
  protocol              = "HTTPS"
  port_name             = "http"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = google_compute_security_policy.edge.id
  enable_cdn            = false

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  backend {
    group = google_compute_region_network_endpoint_group.backend_neg.id
  }
}

# Backend Bucket: フロントエンド静的アセット用 (Cloud CDN 有効)
# AWS の CloudFront default behavior (S3) 相当
#
# 注: Cloud Armor の edge_security_policy には preconfigured WAF (SQLi/XSS 等) を
# アタッチできない制約があるため、フル WAF は API (backend service) 側のみで適用する。
# 静的アセットは攻撃面が小さいため、WAF より rate-limit/DDoS 対策で十分。
resource "google_compute_backend_bucket" "frontend" {
  name        = "${var.app-name}-${var.environment}-frontend"
  bucket_name = google_storage_bucket.web.name
  enable_cdn  = true

  cdn_policy {
    # USE_ORIGIN_HEADERS: GCS にアップロード時に設定した Cache-Control をそのまま尊重
    # index.html に Cache-Control: no-store, no-cache を付与してアップロードする運用で
    # AWS の Managed-CachingDisabled (index.html ビヘイビア) と同等の挙動を実現
    # 注: USE_ORIGIN_HEADERS では client_ttl / default_ttl / max_ttl は GCP API 側で無視され
    #     常に 0 が返るため指定しない (指定すると毎回 0→指定値 の永続差分が発生する)
    cache_mode = "USE_ORIGIN_HEADERS"

    # negative_caching_policy で許可されるコード: [300, 301, 302, 307, 308, 404, 405, 410, 421, 451, 501]
    # 403 は許可リストに含まれないため除外 (該当する場合は notFoundPage 経由で 404 にフォールバック)
    negative_caching = true
    negative_caching_policy {
      code = 404
      ttl  = 10
    }
    negative_caching_policy {
      code = 410
      ttl  = 10
    }
  }

  # edge_security_policy は preconfigured WAF をサポートしないため、
  # 本テンプレートではフル WAF を持つ google_compute_security_policy.edge は使えない。
  # 必要なら IP / rate-limit のみの CLOUD_ARMOR_EDGE タイプの別ポリシーを作成して
  # アタッチする (今回は省略)。
}

# URL Map: パスルーティング + セキュリティヘッダ付与
# - /api/*  → Backend Service (Cloud Run)
# - default → Backend Bucket (GCS)
resource "google_compute_url_map" "main" {
  name            = "${var.app-name}-${var.environment}-urlmap"
  default_service = google_compute_backend_bucket.frontend.id

  # SPA 配信時のセキュリティヘッダ (AWS cloudfront_response_headers_policy.spa 相当)
  default_route_action {
    cors_policy {
      allow_origins = ["*"]
      allow_methods = ["GET", "HEAD", "OPTIONS"]
      max_age       = 3600
      disabled      = false
    }
  }

  header_action {
    response_headers_to_add {
      header_name  = "Strict-Transport-Security"
      header_value = "max-age=31536000; includeSubDomains"
      replace      = true
    }
    response_headers_to_add {
      header_name  = "X-Content-Type-Options"
      header_value = "nosniff"
      replace      = true
    }
    response_headers_to_add {
      header_name  = "X-Frame-Options"
      header_value = "DENY"
      replace      = true
    }
    response_headers_to_add {
      header_name  = "Referrer-Policy"
      header_value = "strict-origin-when-cross-origin"
      replace      = true
    }
    response_headers_to_add {
      header_name  = "X-XSS-Protection"
      header_value = "0"
      replace      = true
    }
    response_headers_to_add {
      header_name  = "Permissions-Policy"
      header_value = "camera=(), microphone=(), geolocation=(), interest-cohort=()"
      replace      = true
    }
    response_headers_to_add {
      header_name = "Content-Security-Policy"
      header_value = join("; ", [
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
      replace = true
    }
  }

  host_rule {
    hosts        = ["*"]
    path_matcher = "main"
  }

  path_matcher {
    name            = "main"
    default_service = google_compute_backend_bucket.frontend.id

    # /api/* → Cloud Run (セキュリティヘッダは backend 側の方針に従い API 用は最小限)
    path_rule {
      paths   = ["/api", "/api/*"]
      service = google_compute_backend_service.backend.id

      route_action {
        # API には CSP / Permissions-Policy を付与しない (AWS の api ポリシーと整合)
        cors_policy {
          allow_origins = ["*"]
          allow_methods = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"]
          allow_headers = ["*"]
          max_age       = 3600
          disabled      = false
        }
      }
    }
  }
}

# HTTPS 用 URL Map: 上記をそのまま利用
# HTTP → HTTPS リダイレクト用 URL Map: 別途定義
resource "google_compute_url_map" "https_redirect" {
  name = "${var.app-name}-${var.environment}-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }

  depends_on = [time_sleep.wait_for_apis]
}

# Google マネージド SSL 証明書
# 注: グローバル LB IP に対する DNS A レコードを別途設定し、ドメイン所有を証明する必要あり
# 本テンプレートでは LB IP 直叩きでも動作するよう、self-managed/managed 両対応のフラグを変数化することも可能
# ここでは最小構成として LB IP 用に self-signed の HTTPS は省略し、HTTPS は managed cert + ドメインを前提とする
resource "google_compute_managed_ssl_certificate" "main" {
  count = var.lb-domain == "" ? 0 : 1
  name  = "${var.app-name}-${var.environment}-cert"

  managed {
    domains = [var.lb-domain]
  }
}

# Target HTTPS Proxy
resource "google_compute_target_https_proxy" "main" {
  count            = var.lb-domain == "" ? 0 : 1
  name             = "${var.app-name}-${var.environment}-https-proxy"
  url_map          = google_compute_url_map.main.id
  ssl_certificates = [google_compute_managed_ssl_certificate.main[0].id]
}

# Target HTTP Proxy (リダイレクト用)
resource "google_compute_target_http_proxy" "main_redirect" {
  count   = var.lb-domain == "" ? 0 : 1
  name    = "${var.app-name}-${var.environment}-http-redirect"
  url_map = google_compute_url_map.https_redirect.id
}

# ドメインが未設定の場合は HTTP のみで動作確認できるようにする (PoC 用)
resource "google_compute_target_http_proxy" "main_http_only" {
  count   = var.lb-domain == "" ? 1 : 0
  name    = "${var.app-name}-${var.environment}-http-proxy"
  url_map = google_compute_url_map.main.id
}

# Global Forwarding Rule: HTTPS:443
resource "google_compute_global_forwarding_rule" "https" {
  count                 = var.lb-domain == "" ? 0 : 1
  name                  = "${var.app-name}-${var.environment}-https"
  ip_address            = google_compute_global_address.lb_ip.address
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_https_proxy.main[0].id
}

# Global Forwarding Rule: HTTP:80 (HTTPS リダイレクト用 / ドメイン未設定時は通常応答)
resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.app-name}-${var.environment}-http"
  ip_address            = google_compute_global_address.lb_ip.address
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = var.lb-domain == "" ? google_compute_target_http_proxy.main_http_only[0].id : google_compute_target_http_proxy.main_redirect[0].id
}
