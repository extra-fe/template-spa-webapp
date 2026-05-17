# VPCフローログ格納用S3バケット(全トラフィックの監査・調査用)
resource "aws_s3_bucket" "vpc_flow_log" {
  bucket = "${var.app-name}-${var.environment}-vpc-flow-log-${random_string.suffix.result}"
  tags = {
    "Name" = "${var.app-name}-${var.environment}-vpc-flow-log"
  }
}

# パブリックアクセス全面ブロック(誤った公開設定を防ぐ)
resource "aws_s3_bucket_public_access_block" "vpc_flow_log" {
  bucket                  = aws_s3_bucket.vpc_flow_log.bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# バージョニング無効化(本テンプレートの他バケットと方針を揃える)
resource "aws_s3_bucket_versioning" "vpc_flow_log" {
  bucket = aws_s3_bucket.vpc_flow_log.bucket

  versioning_configuration {
    status = "Disabled"
  }
}

# バケットポリシー: VPC Flow Logs配信サービス(delivery.logs.amazonaws.com)からの書き込みのみ許可
# Confused Deputy対策として aws:SourceAccount / aws:SourceArn で自アカウント・自リージョンに限定
resource "aws_s3_bucket_policy" "vpc_flow_log" {
  bucket = aws_s3_bucket.vpc_flow_log.bucket
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSLogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.vpc_flow_log.arn}/AWSLogs/${data.aws_caller_identity.self.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = data.aws_caller_identity.self.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.self.account_id}:*"
          }
        }
      },
      {
        Sid       = "AWSLogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action = [
          "s3:GetBucketAcl",
          "s3:ListBucket",
        ]
        Resource = aws_s3_bucket.vpc_flow_log.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.self.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.self.account_id}:*"
          }
        }
      },
    ]
  })
}

# VPC全体のフローログをS3へ出力(全トラフィック=ACCEPT/REJECT両方を記録)
# 集約間隔は10分(600秒)=デフォルト値で、コストとリアルタイム性のバランスを取る
resource "aws_flow_log" "vpc" {
  vpc_id                   = aws_vpc.vpc.id
  traffic_type             = "ALL"
  log_destination_type     = "s3"
  log_destination          = aws_s3_bucket.vpc_flow_log.arn
  max_aggregation_interval = 600
  tags = {
    "Name" = "${var.app-name}-${var.environment}-vpc-flow-log"
  }
}
