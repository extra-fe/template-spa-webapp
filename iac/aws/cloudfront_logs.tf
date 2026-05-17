# CloudFront 標準アクセスログ (v2 CloudWatch Logs Delivery 経由でS3配信)
#
# レガシー方式 (aws_cloudfront_distribution.logging_config) はS3バケットにACL有効化と
# `awslogsdelivery@amazon.com` への ACL grant が必須で、本プロジェクトの
# `block_public_acls = true` ポリシーと噛み合わない。
# よって v2 方式 (aws_cloudwatch_log_delivery_*) を採用 — バケットポリシーのみで配信可能。
#
# 注意: CloudFront は us-east-1 リージョンの API で管理されるため、
# log_delivery_source / destination / delivery の3リソースはすべて us-east-1 プロバイダを使う。
# S3バケット自体は ap-northeast-1 のままで問題ない (リージョン間配信可)。

# CloudFrontアクセスログ用S3バケット
resource "aws_s3_bucket" "cloudfront_logs" {
  bucket        = "${var.app-name}-${var.environment}-cf-logs-${random_string.suffix.result}"
  force_destroy = true
  tags          = {}
}

resource "aws_s3_bucket_public_access_block" "cloudfront_logs" {
  bucket                  = aws_s3_bucket.cloudfront_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Standard → Standard-IA(31日) → Glacier(365日) でALB/ECSログと同じ階層化
resource "aws_s3_bucket_lifecycle_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
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

# CloudWatch Logs Delivery がバケットに書き込むための権限
# (delivery.logs.amazonaws.com サービスプリンシパルに対する PutObject / GetBucketAcl 等)
resource "aws_s3_bucket_policy" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowLogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudfront_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = data.aws_caller_identity.self.account_id
          }
        }
      },
      {
        Sid       = "AllowLogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = aws_s3_bucket.cloudfront_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.self.account_id
          }
        }
      }
    ]
  })
}

# CloudFrontディストリビューションをログ配信元として登録
# (CloudFrontがグローバルサービスのため us-east-1 で作成)
resource "aws_cloudwatch_log_delivery_source" "cloudfront" {
  provider     = aws.us_east_1
  name         = "${var.app-name}-${var.environment}-cf-access-source"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.cdn.arn
}

# S3を配信先として登録
# json フォーマット: CloudFront フィールド名 (cs-method, cs(Host) 等) をそのまま JSON キーとして出力。
# Athena 側で JsonSerDe の mapping パラメータでハイフン/括弧を含むキーを安全な列名へ変換する。
# (parquet は列名に特殊文字を含むため Glue API での定義が困難なため json を採用)
resource "aws_cloudwatch_log_delivery_destination" "cloudfront" {
  provider      = aws.us_east_1
  name          = "${var.app-name}-${var.environment}-cf-access-dest"
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_s3_bucket.cloudfront_logs.arn
  }
}

# 配信元と配信先を紐付け
# suffix_path で年月日時パーティションをS3キーに含める (Athena partition projection 用)
#
# CW Logs Delivery は自動プレフィックスを付与しない。suffix_path がそのまま S3 キーになる。
# suffix_path = "{dist-id}/{yyyy}/{MM}/{dd}/{HH}" → 実際のS3キー: {dist-id}/{yyyy}/{MM}/{dd}/{HH}/filename.gz
resource "aws_cloudwatch_log_delivery" "cloudfront" {
  provider                 = aws.us_east_1
  delivery_source_name     = aws_cloudwatch_log_delivery_source.cloudfront.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cloudfront.arn

  s3_delivery_configuration {
    suffix_path                 = "${aws_cloudfront_distribution.cdn.id}/{yyyy}/{MM}/{dd}/{HH}"
    enable_hive_compatible_path = false
  }

  depends_on = [aws_s3_bucket_policy.cloudfront_logs]
}

