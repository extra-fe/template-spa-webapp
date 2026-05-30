# Terraform state 専用 S3 バケット
#
# 既存のログ用バケット等とは分離し、state 専用に作成する (Issue #138)。
# 名前は ${app}-${env}-tfstate-${アカウントID} でグローバル一意にする。
# ロックは S3 ネイティブロック (backend 側 use_lockfile = true) を使うため
# DynamoDB テーブルは不要。
resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.app-name}-${var.environment}-tfstate-${data.aws_caller_identity.self.account_id}"
  tags   = {}
}

# パブリックアクセス全面ブロック (state には機密が含まれるため必須)
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# バージョニング有効化 (state 破損時のロールバック手段を確保)
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# サーバサイド暗号化 (SSE-S3 / AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# 古い state バージョンの肥大化を防ぐライフサイクル
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-state"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# HTTPS 以外のアクセスを拒否 (転送中の暗号化を強制)
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })
}
