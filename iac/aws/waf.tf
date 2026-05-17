# AWS WAF v2 (CloudFront用): CloudFrontディストリビューションへアタッチして
# 一般的な攻撃パターンを遮断する。
#
# 配置リージョン: us-east-1
#   - scope = "CLOUDFRONT" の WAF は us-east-1 でしか作れない
#   - WAFログ配信先S3バケットも同じ us-east-1 でないと直接配信できない
#   - そのため WAF 関連リソース + WAFログ用S3バケットはすべて `aws.us_east_1` プロバイダで作成
#
# ルール構成 (デフォルトルール: AWSマネージドルールグループ 3種):
#   1. AWSManagedRulesCommonRuleSet         (OWASP Top10系の汎用攻撃検知)
#   2. AWSManagedRulesKnownBadInputsRuleSet (既知の悪性ペイロード検知)
#   3. AWSManagedRulesAmazonIpReputationList(AWS収集の悪性IP遮断)
# default_action = allow (ルールにマッチしたものだけブロック)

resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1
  name     = "${var.app-name}-${var.environment}-cf-acl"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # ルール1: 一般的な攻撃パターン (XSS / SQLi / LFI 等)
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {} # マネージドルールグループ既定のアクション(主にblock)をそのまま使う
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ルール2: 既知の悪性ペイロード (Log4Shell 等含む)
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ルール3: AWS収集の悪性IPレピュテーションリスト
  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.app-name}-${var.environment}-cf-acl"
    sampled_requests_enabled   = true
  }
}

# WAFログ用S3バケット (us-east-1)
#
# 重要制約:
#   - バケット名は "aws-waf-logs-" プレフィックスで開始すること (AWS WAFの仕様)
#   - WAF (CLOUDFRONT scope) と同リージョン (us-east-1) であること
resource "aws_s3_bucket" "waf_logs" {
  provider      = aws.us_east_1
  bucket        = "aws-waf-logs-${var.app-name}-${var.environment}-${random_string.suffix.result}"
  force_destroy = true
  tags          = {}
}

resource "aws_s3_bucket_public_access_block" "waf_logs" {
  provider                = aws.us_east_1
  bucket                  = aws_s3_bucket.waf_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Standard → Standard-IA(31日) → Glacier(365日) でALB/ECS/CFログと同じ階層化
resource "aws_s3_bucket_lifecycle_configuration" "waf_logs" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.waf_logs.id
  rule {
    id     = "tiering"
    status = "Enabled"
    filter {}
    transition {
      days          = 31
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }
}

# WAFログ配信用バケットポリシー
# (delivery.logs.amazonaws.com に PutObject / GetBucketAcl を許可)
resource "aws_s3_bucket_policy" "waf_logs" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.waf_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSLogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.waf_logs.arn}/AWSLogs/${data.aws_caller_identity.self.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = data.aws_caller_identity.self.account_id
          }
        }
      },
      {
        Sid       = "AWSLogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.waf_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.self.account_id
          }
        }
      }
    ]
  })
}

# WAF → S3 ログ配信設定
# log_destination_configs に S3バケットARNを指定すれば Firehose 不要で直接配信
resource "aws_wafv2_web_acl_logging_configuration" "cloudfront" {
  provider                = aws.us_east_1
  log_destination_configs = [aws_s3_bucket.waf_logs.arn]
  resource_arn            = aws_wafv2_web_acl.cloudfront.arn

  depends_on = [aws_s3_bucket_policy.waf_logs]
}

# NOTE: WAFログ用のAthena/Glueテーブルは別途追加可能。
# WAFログはJSON形式で 1行1リクエスト・スキーマがマネージドルール構成に依存するため、
# 初期配信後に実データを確認してから JsonSerDe ベースの Glue テーブルを後追いで作成する想定。
# また Athena ワークグループ自体が ap-northeast-1 にしか無いため、
# クロスリージョンクエリ(us-east-1のバケットを直接クエリ)か、
# us-east-1 にも Athena ワークグループを作るか、要判断。
