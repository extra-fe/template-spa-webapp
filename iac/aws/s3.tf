# 静的Webアセット配信用S3バケット(CloudFront経由でのみ公開)
resource "aws_s3_bucket" "web" {
  bucket = "${var.app-name}-${var.environment}-web-${random_string.suffix.result}"
  tags   = {}
}

# パブリックアクセス全面ブロック(誤った公開設定を防ぐ)
resource "aws_s3_bucket_public_access_block" "web" {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.web.bucket
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# サーバサイド暗号化 (SSE-S3 / AES256): 2023年以降のAWSデフォルトを明示化
resource "aws_s3_bucket_server_side_encryption_configuration" "web" {
  bucket = aws_s3_bucket.web.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# バージョニング無効化(本テンプレートではロールバック運用しないため)
resource "aws_s3_bucket_versioning" "web" {
  bucket = aws_s3_bucket.web.bucket

  versioning_configuration {
    status = "Disabled"
  }
}

# バケットポリシー: CloudFrontディストリビューションからのGetObjectのみ許可
resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.bucket
  policy = jsonencode(
    {
      Id = "PolicyForCloudFrontPrivateContent"
      Statement = [
        {
          Action = "s3:GetObject"
          Condition = {
            StringEquals = {
              "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
            }
          }
          Effect = "Allow"
          Principal = {
            Service = "cloudfront.amazonaws.com"
          }
          Resource = "${aws_s3_bucket.web.arn}/*"
          Sid      = "AllowCloudFrontServicePrincipal"
        },
      ]
      Version = "2008-10-17"
    }
  )
}
