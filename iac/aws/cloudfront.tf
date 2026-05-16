# AWSが管理する標準キャッシュポリシー(高効率キャッシュ): フロント静的アセット用
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

# フロントエンド(S3オリジン)識別子
locals {
  frontend_origin_id = "${var.app-name}-${var.environment}-frontend"
}

# Origin Access Control: CloudFrontからS3への署名付きアクセスを必須化
resource "aws_cloudfront_origin_access_control" "oac" {
  description                       = null
  name                              = "${var.app-name}-${var.environment}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFrontディストリビューション: ユーザ向けの唯一のエンドポイント
# - 既定ビヘイビアは S3(フロント) を返す
# - /api/* は VPC Origin 経由で内部ALBへ転送
# - 403 を index.html へリライト(SPAクライアントサイドルーティング対応)
resource "aws_cloudfront_distribution" "cdn" {
  enabled         = true
  http_version    = "http2"
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"
  tags            = {}

  default_cache_behavior {
    allowed_methods = [
      "GET",
      "HEAD",
      "OPTIONS",
    ]
    cache_policy_id = data.aws_cloudfront_cache_policy.optimized.id
    cached_methods = [
      "GET",
      "HEAD",
    ]
    compress               = true
    target_origin_id       = local.frontend_origin_id
    viewer_protocol_policy = "redirect-to-https"
  }

  # オリジン1: フロント配信用 S3 バケット
  origin {
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id                = local.frontend_origin_id
  }

  # オリジン2: 内部ALB(VPC Origin経由)
  origin {
    domain_name = aws_lb.alb.dns_name
    origin_id   = local.backend_origin_id

    vpc_origin_config {
      vpc_origin_id = aws_cloudfront_vpc_origin.alb.id
    }
  }

  # /api/* 用追加ビヘイビア: キャッシュ無効・全ヘッダ転送でAPI挙動を素通し
  ordered_cache_behavior {
    path_pattern             = var.api-base-path
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
    target_origin_id         = local.backend_origin_id
    viewer_protocol_policy   = "allow-all"
    allowed_methods          = ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"]
    cached_methods           = ["GET", "HEAD"]
  }

  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  # SPAルーティング対応: S3で見つからない(403)場合は index.html を返す
  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1"
  }
}

# バックエンド(ALBオリジン)識別子
locals {
  backend_origin_id = "${var.app-name}-${var.environment}-backend"
}

# CloudFront VPC Origin: 内部ALB(internal=true)をCloudFrontオリジンとして利用するための仕組み
resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = local.backend_origin_id
    arn                    = aws_lb.alb.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

# AWS管理のキャッシュ無効ポリシー: APIレスポンスのキャッシュを抑止
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# AWS管理のオリジンリクエストポリシー: 全てのビューワヘッダ/Cookieをオリジンへ転送
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}
