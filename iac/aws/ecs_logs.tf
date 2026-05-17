# ECSアプリケーションログ用S3バケット (Fluent Bit/FireLens経由で書き込む)
resource "aws_s3_bucket" "ecs_logs" {
  bucket        = "${var.app-name}-${var.environment}-ecs-logs-${random_string.suffix.result}"
  force_destroy = true
  tags          = {}
}

resource "aws_s3_bucket_public_access_block" "ecs_logs" {
  bucket                  = aws_s3_bucket.ecs_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Standard → Standard-IA(31日) → Glacier(365日) で長期保存
resource "aws_s3_bucket_lifecycle_configuration" "ecs_logs" {
  bucket = aws_s3_bucket.ecs_logs.id
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

# Fluent Bit設定ファイル用S3バケット
resource "aws_s3_bucket" "fluent_bit_config" {
  bucket        = "${var.app-name}-${var.environment}-fluent-bit-config-${random_string.suffix.result}"
  force_destroy = true
  tags          = {}
}

resource "aws_s3_bucket_public_access_block" "fluent_bit_config" {
  bucket                  = aws_s3_bucket.fluent_bit_config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Fluent Bit設定: ヘルスチェック除外 → CloudWatch Logs(7日) + S3 に二重出力
resource "aws_s3_object" "fluent_bit_config" {
  bucket = aws_s3_bucket.fluent_bit_config.id
  key    = "fluent-bit.conf"
  content = <<-EOT
[FILTER]
    Name    grep
    Match   *
    Exclude log ${var.health-check-path}

[OUTPUT]
    Name              cloudwatch_logs
    Match             *
    region            ${data.aws_region.current.region}
    log_group_name    ${aws_cloudwatch_log_group.backend.name}
    log_stream_prefix ecs/
    auto_create_group false

[OUTPUT]
    Name              s3
    Match             *
    region            ${data.aws_region.current.region}
    bucket            ${aws_s3_bucket.ecs_logs.bucket}
    s3_key_format     /ecs-logs/%Y/%m/%d/%H%M%S
    compression       gzip
    total_file_size   50M
    upload_timeout    10m
EOT
}

# FireLensコンテナ(log_router)自身のログ用ロググループ
resource "aws_cloudwatch_log_group" "firelens" {
  name              = "/ecs/firelens/${var.app-name}-${var.environment}"
  retention_in_days = 7
}

# タスクロール: Fluent BitがCloudWatch Logsへ書き込む + S3へ書き込む権限
resource "aws_iam_role_policy" "ecs_task_firelens" {
  name = "firelens-output"
  role = aws_iam_role.ecs_task.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.backend.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.ecs_logs.arn}/*"
      }
    ]
  })
}

# タスク実行ロール: ECSエージェントがFluentBit設定ファイルをS3から取得する権限
resource "aws_iam_role_policy" "execute_ecs_task_fluent_bit" {
  name = "fluent-bit-config"
  role = aws_iam_role.execute_ecs_task.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "${aws_s3_bucket.fluent_bit_config.arn}",
          "${aws_s3_bucket.fluent_bit_config.arn}/*"
        ]
      }
    ]
  })
}
