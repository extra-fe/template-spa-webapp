resource "aws_lb" "alb" {
  drop_invalid_header_fields = false
  enable_deletion_protection = false
  enable_http2               = true
  idle_timeout               = 60
  internal                   = true
  ip_address_type            = "ipv4"
  load_balancer_type         = "application"
  name                       = "${var.app-name}-${var.environment}-alb"
  security_groups = [
    aws_security_group.alb.id,
  ]
  subnets = [
    aws_subnet.private1a.id,
    aws_subnet.private1c.id,
  ]
  tags = {}
  access_logs {
    enabled = true                      # 変更
    bucket  = aws_s3_bucket.alb_logs.id # 変更
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  tags              = {}
  default_action {
    order = 1
    type  = "fixed-response"
    fixed_response {
      status_code  = 404
      message_body = ""
      content_type = "text/plain"
    }
  }
}

resource "aws_lb_listener_rule" "from_cloudfront" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1
  tags         = {}
  action {
    order            = 10
    target_group_arn = aws_lb_target_group.to_ecs_service.arn
    type             = "forward"
  }
  condition {
    path_pattern {
      values = [
        var.api-base-path,
      ]
    }
  }
}


resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.app-name}-${var.environment}-alb-logs-${random_string.suffix.result}"
  force_destroy = true
  tags          = {}
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire"
    status = "Enabled"

    expiration {
      days = 30 # 必要に応じて変更
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/AWSLogs/${data.aws_caller_identity.self.account_id}/*"
      }
    ]
  })
}

# Athenaクエリ結果用S3バケット
resource "aws_s3_bucket" "athena_results" {
  bucket        = "${var.app-name}-${var.environment}-athena-results-${random_string.suffix.result}"
  force_destroy = true
  tags          = {}
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    id     = "expire"
    status = "Enabled"

    expiration {
      days = 7
    }
  }
}

# Athenaワークグループ
resource "aws_athena_workgroup" "alb_logs" {
  name          = "${var.app-name}-${var.environment}-alb-logs"
  force_destroy = true

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"
    }
  }
}

# AthenaデータベースDB
resource "aws_athena_database" "alb_logs" {
  name   = "${replace(var.app-name, "-", "_")}_${var.environment}_alb_logs"
  bucket = aws_s3_bucket.athena_results.bucket
}


