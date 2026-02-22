## 外部 IP アドレス (LB用)
resource "google_compute_global_address" "lb-ip" {
  name = "${var.app-name}-${var.environment}-lb-ip"
}

## バックエンドバケット (GCS → Cloud CDN)
resource "google_compute_backend_bucket" "frontend" {
  name        = "${var.app-name}-${var.environment}-frontend-bucket"
  bucket_name = google_storage_bucket.frontend.name
  enable_cdn  = true

  cdn_policy {
    cache_mode                   = "CACHE_ALL_STATIC"
    default_ttl                  = 3600
    max_ttl                      = 86400
    serve_while_stale            = 86400
    signed_url_cache_max_age_sec = 0
  }
}

## Serverless NEG (Cloud Run バックエンド)
resource "google_compute_region_network_endpoint_group" "backend" {
  name                  = "${var.app-name}-${var.environment}-backend-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_v2_service.backend.name
  }
}

## バックエンドサービス (Cloud Run)
resource "google_compute_backend_service" "backend" {
  name                  = "${var.app-name}-${var.environment}-backend-service"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.backend.id
  }

  health_checks = [google_compute_health_check.backend.id]

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

## ヘルスチェック (Cloud Run)
resource "google_compute_health_check" "backend" {
  name               = "${var.app-name}-${var.environment}-backend-hc"
  check_interval_sec = 30
  timeout_sec        = 5

  http_health_check {
    port_specification = "USE_SERVING_PORT"
    request_path       = var.health-check-path
  }
}

## URL Map (パスベースルーティング)
## /* → GCS (フロントエンド)
## /api/* → Cloud Run (バックエンド)
resource "google_compute_url_map" "default" {
  name            = "${var.app-name}-${var.environment}-url-map"
  default_service = google_compute_backend_bucket.frontend.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "default"
  }

  path_matcher {
    name            = "default"
    default_service = google_compute_backend_bucket.frontend.id

    path_rule {
      paths   = ["/api", "/api/*"]
      service = google_compute_backend_service.backend.id
    }

    path_rule {
      paths   = ["/health"]
      service = google_compute_backend_service.backend.id
    }
  }
}

## HTTPS プロキシ (マネージド SSL 証明書なし、HTTP のみ)
## 本番環境ではマネージド SSL 証明書を設定する
resource "google_compute_target_http_proxy" "default" {
  name    = "${var.app-name}-${var.environment}-http-proxy"
  url_map = google_compute_url_map.default.id
}

## フォワーディングルール (HTTP)
resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.app-name}-${var.environment}-http-rule"
  ip_address            = google_compute_global_address.lb-ip.address
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.default.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
